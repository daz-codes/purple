module Content
  # Loads all game content from YAML into the database:
  #
  #   content/techniques.yml            the technique vocabulary (ATT&CK-mapped)
  #   content/badges.yml                badges players can earn
  #   content/paths/<path>/_path.yml   a path's details, and how it opens
  #   content/paths/<path>/<track>/_track.yml     a track's details
  #   content/paths/<path>/<track>/<mission>.yml  one file per mission
  #   content/bots.yml                  the Blue bots that judge Red's Workshop emails
  #   content/targets/<target>.yml      one file per Red's Workshop target
  #
  # Everything is upserted by key or slug in a single transaction, so running it twice changes
  # nothing and any error leaves the database as it was. Paths, tracks and missions whose files have
  # gone are unpublished rather than deleted, so players' past attempts keep their history.
  class Import
    Summary = Data.define(:techniques, :badges, :paths, :tracks, :missions, :messages, :bots, :targets) do
      def to_s
        "Imported #{techniques} techniques, #{badges} badges, #{paths} paths, #{tracks} tracks, #{missions} missions, #{messages} messages, " \
          "#{bots} bots and #{targets} targets."
      end
    end

    TECHNIQUE_KEYS = %i[ key name attack_id category description defence_tip red_cost stealth red_flag_label ].freeze
    BADGE_KEYS = %i[ key name description side ].freeze
    BOT_KEYS = %i[ key name description vigilance detects ].freeze
    PATH_KEYS = %i[ title description position opens published ].freeze
    PATH_FILE = "_path.yml".freeze
    TRACK_KEYS = %i[ title description position difficulty unlock_after daily published ].freeze
    TRACK_FILE = "_track.yml".freeze

    def initialize(root = Rails.root.join("content"))
      @root = Pathname(root)
    end

    # Imports everything and returns a Summary of what's now in the database.
    def run
      ActiveRecord::Base.transaction do
        techniques = import_techniques
        badges = import_badges
        paths, tracks, missions = import_paths(techniques)
        bots = import_bots(techniques)
        targets = import_targets(missions, techniques)

        Summary.new(techniques: techniques.size, badges: badges.size, paths: paths.size, tracks: tracks.size, missions: missions.size,
                    messages: Message.where(mission: missions).count, bots: bots.size, targets: targets.size)
      end
    end

    private
      def import_techniques
        file = load(@root.join("techniques.yml"))
        techniques = file.each_item(:techniques) do |node|
          node.allow_only!(*TECHNIQUE_KEYS)
          technique = Technique.find_or_initialize_by(key: node.required(:key))
          node.saving do
            technique.update!(
              name: fictional_text(node, :name), attack_id: node.optional(:attack_id),
              category: node.required(:category), description: fictional_text(node, :description),
              defence_tip: fictional_text(node, :defence_tip), red_cost: node.required(:red_cost, Integer),
              stealth: node.required(:stealth, Integer), red_flag_label: fictional_text(node, :red_flag_label)
            )
          end
          technique
        end
        file.check_unique!("technique", techniques.map(&:key))
        techniques.index_by(&:key)
      end

      def import_badges
        file = load(@root.join("badges.yml"))
        badges = file.each_item(:badges) do |node, index|
          node.allow_only!(*BADGE_KEYS)
          badge = Badge.find_or_initialize_by(key: node.required(:key))
          node.saving do
            badge.update!(name: fictional_text(node, :name), description: fictional_text(node, :description),
                          side: node.required(:side), position: index + 1)
          end
          badge
        end
        file.check_unique!("badge", badges.map(&:key))
        badges
      end

      def import_paths(techniques)
        paths_dir = @root.join("paths")
        raise ImportError.new("no paths folder found at #{relative(paths_dir)}") unless paths_dir.directory?

        path_dirs = paths_dir.children.select(&:directory?).sort
        raise ImportError.new("no path folders found in #{relative(paths_dir)}") if path_dirs.empty?

        nodes = path_dirs.to_h { |dir| import_path(dir) }
        paths = nodes.keys
        nodes.each { |path, node| import_opening(path, node, paths.index_by(&:slug)) }
        check_openings_finish!(paths)

        tracks = []
        missions = []
        path_dirs.zip(paths).each do |dir, path|
          dir.children.select(&:directory?).sort.each do |track_dir|
            if (clash = tracks.find { |track| track.slug == track_dir.basename.to_s })
              raise ImportError.new("a track called #{clash.slug} already exists in the #{clash.path.slug} path",
                                    file: relative(track_dir))
            end
            track = import_track(track_dir, path)
            tracks << track

            track_dir.glob("*.yml").reject { |file| file.basename.to_s == TRACK_FILE }.sort.each do |file|
              if (clash = missions.find { |mission| mission.slug == file.basename(".yml").to_s })
                raise ImportError.new("a mission called #{clash.slug} already exists in the #{clash.track.slug} track",
                                      file: relative(file))
              end
              missions << MissionImport.new(load(file), track:, techniques:, dir: file.dirname).run
            end
          end
        end

        Path.where.not(id: paths.map(&:id)).update_all(published: false)
        Track.where.not(id: tracks.map(&:id)).update_all(published: false)
        Mission.where.not(id: missions.map(&:id)).update_all(published: false)
        check_tracks_can_open!(tracks)
        check_daily_track!(tracks)
        [ paths, tracks, missions ]
      end

      # Each listed track's unlock_after must be reachable: no more than the missions on the track before
      # it, and nothing at all for a path's first track.
      def check_tracks_can_open!(tracks)
        tracks.reject(&:daily?).select(&:published?).group_by(&:path).each_value do |path_tracks|
          playable = path_tracks.select { |track| track.missions.published.exists? }.sort_by(&:position)
          playable.each_cons(2) do |previous, track|
            available = previous.missions.published.count
            next if track.unlock_after <= available

            raise ImportError.new("unlock_after is #{track.unlock_after}, but #{previous.slug} only has #{available} " \
                                  "#{"mission".pluralize(available)}", file: "#{track.path.slug}/#{track.slug}/#{TRACK_FILE}")
          end
          first = playable.first
          if first&.unlock_after&.positive?
            raise ImportError.new("unlock_after must be 0 on a path's first track", file: "#{first.path.slug}/#{first.slug}/#{TRACK_FILE}")
          end
        end
      end

      # The Intercept of the day comes from one daily track of signals missions.
      def check_daily_track!(tracks)
        daily = tracks.select(&:daily?)
        raise ImportError.new("only one track can be daily (#{daily.map(&:slug).join(", ")})") if daily.size > 1
        return if daily.empty?

        track = daily.first
        file = "#{track.path.slug}/#{track.slug}/#{TRACK_FILE}"
        raise ImportError.new("a daily track can't have unlock_after", file:) if track.unlock_after.positive?
        raise ImportError.new("a daily track holds only signals missions", file:) unless track.missions.all?(&:kind_signals?)
      end

      # Saves a path's details and returns it with its node, so how it opens can be read once every
      # path exists. A new path opens always until then.
      def import_path(dir)
        file = dir.join(PATH_FILE)
        raise ImportError.new("is missing #{PATH_FILE}", file: relative(dir)) unless file.exist?

        node = load(file)
        node.allow_only!(*PATH_KEYS)
        path = Path.find_or_initialize_by(slug: dir.basename.to_s)
        path.opens = "always" if path.new_record?
        node.saving do
          path.update!(title: fictional_text(node, :title), description: fictional_text(node, :description),
                       position: node.optional(:position, Integer, default: 0),
                       published: node.optional(:published, Node::BOOLEAN, default: true))
        end
        [ path, node ]
      end

      # opens: always (the default) | { after_missions: 3 } | { after_first_track_of: <path slug> }
      def import_opening(path, node, paths_by_slug)
        opening = { opens: "always", opens_after_missions: nil, opens_after_path: nil }
        if node.mapping?(:opens)
          opens = node.child(:opens)
          opens.allow_only!(:after_missions, :after_first_track_of)
          if opens.key?(:after_missions) == opens.key?(:after_first_track_of)
            opens.error!("give one of after_missions or after_first_track_of")
          elsif opens.key?(:after_missions)
            opening.merge!(opens: "after_missions", opens_after_missions: opens.required(:after_missions, Integer))
          else
            slug = opens.required(:after_first_track_of)
            other = paths_by_slug[slug] || opens.error!("after_first_track_of names no path in the content: #{slug}")
            opening.merge!(opens: "after_first_track", opens_after_path: other)
          end
        elsif node.optional(:opens, default: "always") != "always"
          node.error!("opens must be always, or a mapping with after_missions or after_first_track_of")
        end
        node.saving { path.update!(opening) }
      end

      # A path that waits on another path's first track must never, through others, wait on itself.
      def check_openings_finish!(paths)
        paths.each do |path|
          chain = [ path ]
          while (path = path.opens_after_path)
            if chain.include?(path)
              raise ImportError.new("paths wait on each other in a loop: #{(chain + [ path ]).map(&:slug).join(" → ")}")
            end
            chain << path
          end
        end
      end

      def import_track(dir, path)
        file = dir.join(TRACK_FILE)
        raise ImportError.new("is missing #{TRACK_FILE}", file: relative(dir)) unless file.exist?

        node = load(file)
        node.allow_only!(*TRACK_KEYS)
        track = Track.find_or_initialize_by(slug: dir.basename.to_s)
        node.saving do
          track.update!(path:, title: fictional_text(node, :title), description: fictional_text(node, :description),
                        position: node.optional(:position, Integer, default: 0),
                        difficulty: node.required(:difficulty),
                        unlock_after: node.optional(:unlock_after, Integer, default: 0),
                        daily: node.optional(:daily, Node::BOOLEAN, default: false),
                        published: node.optional(:published, Node::BOOLEAN, default: true))
        end
        track
      end

      def import_bots(techniques)
        file = load(@root.join("bots.yml"))
        bots = file.each_item(:bots) do |node, index|
          node.allow_only!(*BOT_KEYS)
          detects = node.optional(:detects, Hash, default: {})
          detects.each do |key, bonus|
            node.error!("detects: unknown technique \"#{key}\"") unless techniques.key?(key.to_s)
            node.error!("detects: #{key} must be a whole number") unless bonus.is_a?(Integer)
          end

          bot = BotPersona.find_or_initialize_by(key: node.required(:key))
          node.saving do
            bot.update!(name: fictional_text(node, :name), description: fictional_text(node, :description),
                        vigilance: node.required(:vigilance, Integer), detects: detects.transform_keys(&:to_s), position: index + 1)
          end
          bot
        end
        file.check_unique!("bot", bots.map(&:key))
        BotPersona.where.not(id: bots.map(&:id)).destroy_all
        bots
      end

      def import_targets(missions, techniques)
        dir = @root.join("targets")
        return [] unless dir.directory?

        targets = dir.glob("*.yml").sort.map { |file| TargetImport.new(load(file), missions:, techniques:).run }
        Target.where.not(id: targets.map(&:id)).update_all(published: false)
        targets
      end

      def fictional_text(node, key)
        node.check_fictional!(key, node.required(key))
      end

      def load(file)
        raise ImportError.new("file not found", file: relative(file)) unless file.exist?

        Node.load_file(file, root: @root)
      end

      def relative(path)
        path.relative_path_from(@root.parent).to_s
      end
  end
end
