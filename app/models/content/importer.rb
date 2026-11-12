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
                    messages: shifts.sum { |shift| shift.messages.count })
      end
    end

    private
      def import_techniques
        load(@root.join("techniques.yml")).each_item(:techniques) do |node|
          node.allow_only!(*TECHNIQUE_KEYS)
          technique = Technique.find_or_initialize_by(key: node.required(:key))
          node.saving do
            technique.update!(
              name: node.required(:name), attack_id: node.optional(:attack_id),
              category: node.required(:category), description: node.required(:description),
              defence_tip: node.required(:defence_tip), red_cost: node.required(:red_cost, Integer),
              stealth: node.required(:stealth, Integer), red_flag_label: node.required(:red_flag_label)
            )
          end
          technique
        end.index_by(&:key)
      end

      def import_badges
        load(@root.join("badges.yml")).each_item(:badges) do |node, index|
          node.allow_only!(*BADGE_KEYS)
          badge = Badge.find_or_initialize_by(key: node.required(:key))
          node.saving do
            badge.update!(name: node.required(:name), description: node.required(:description),
                          side: node.required(:side), position: index + 1)
          end
          badge
        end
      end

      def import_tracks(techniques)
        track_dirs = @root.join("tracks").children.select(&:directory?).sort
        raise ImportError.new("no track folders found in #{@root.join("tracks")}") if track_dirs.empty?

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
          track.update!(title: node.required(:title), description: node.required(:description),
                        position: node.optional(:position, Integer, default: 0),
                        difficulty: node.required(:difficulty),
                        published: node.optional(:published, Node::BOOLEAN, default: true))
        end
        track
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
