module Content
  # Loads all game content from YAML into the database:
  #
  #   content/techniques.yml            the technique vocabulary (ATT&CK-mapped)
  #   content/badges.yml                badges players can earn
  #   content/tracks/<track>/_track.yml a track's details
  #   content/tracks/<track>/<shift>.yml one file per shift
  #
  # Everything is upserted by key or slug in a single transaction, so running it twice changes
  # nothing and any error leaves the database as it was. Tracks and shifts whose files have gone
  # are unpublished rather than deleted, so players' past attempts keep their history.
  class Importer
    Summary = Data.define(:techniques, :badges, :tracks, :shifts, :messages) do
      def to_s
        "Imported #{techniques} techniques, #{badges} badges, #{tracks} tracks, #{shifts} shifts and #{messages} messages."
      end
    end

    TECHNIQUE_KEYS = %i[ key name attack_id category description defence_tip red_cost stealth red_flag_label ].freeze
    BADGE_KEYS = %i[ key name description side ].freeze
    TRACK_KEYS = %i[ title description position difficulty published ].freeze
    TRACK_FILE = "_track.yml".freeze

    def self.call(root = Rails.root.join("content"))
      new(root).call
    end

    def initialize(root)
      @root = Pathname(root)
    end

    def call
      ActiveRecord::Base.transaction do
        techniques = import_techniques
        badges = import_badges
        tracks, shifts = import_tracks(techniques)

        Summary.new(techniques: techniques.size, badges: badges.size, tracks: tracks.size, shifts: shifts.size,
                    messages: Message.where(shift: shifts).count)
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

      def import_tracks(techniques)
        tracks_dir = @root.join("tracks")
        raise ImportError.new("no tracks folder found at #{relative(tracks_dir)}") unless tracks_dir.directory?

        track_dirs = tracks_dir.children.select(&:directory?).sort
        raise ImportError.new("no track folders found in #{relative(tracks_dir)}") if track_dirs.empty?

        tracks = []
        shifts = []
        track_dirs.each do |dir|
          track = import_track(dir)
          tracks << track

          dir.glob("*.yml").reject { |file| file.basename.to_s == TRACK_FILE }.sort.each do |file|
            if (clash = shifts.find { |shift| shift.slug == file.basename(".yml").to_s })
              raise ImportError.new("a shift called #{clash.slug} already exists in the #{clash.track.slug} track",
                                    file: relative(file))
            end
            shifts << ShiftImport.new(load(file), track:, techniques:).call
          end
        end

        Track.where.not(id: tracks.map(&:id)).update_all(published: false)
        Shift.where.not(id: shifts.map(&:id)).update_all(published: false)
        [ tracks, shifts ]
      end

      def import_track(dir)
        file = dir.join(TRACK_FILE)
        raise ImportError.new("is missing #{TRACK_FILE}", file: relative(dir)) unless file.exist?

        node = load(file)
        node.allow_only!(*TRACK_KEYS)
        track = Track.find_or_initialize_by(slug: dir.basename.to_s)
        node.saving do
          track.update!(title: fictional_text(node, :title), description: fictional_text(node, :description),
                        position: node.optional(:position, Integer, default: 0),
                        difficulty: node.required(:difficulty),
                        published: node.optional(:published, Node::BOOLEAN, default: true))
        end
        track
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
