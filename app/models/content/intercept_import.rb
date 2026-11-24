module Content
  # Validates and upserts a signals mission's intercepts by key, deleting any no longer in the file.
  #
  # An intercept is one of:
  #   encode: [ { vigenere: CRUMPET }, to_base64 ]   the solution, encoded by this recipe (Intercept::Cipher)
  #   body: "..."                                    text given as it is, such as a log
  #   file: harbour-photo.png                        a file in the track's files/ folder
  #
  # The solution is what the player recovers, and every flag must appear in it, so a flag is always a
  # fact the puzzle gives up. An encoded intercept is checked to decode back to its solution.
  class InterceptImport
    KEYS = %i[ key title source question solution explanation encode body file flag flags points ].freeze
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    FILES_DIR = "files".freeze
    # What a file must start with to be the type its extension says.
    FILE_SIGNATURES = { "image/png" => "\x89PNG\r\n\x1A\n".b, "application/pdf" => "%PDF-".b }.freeze

    def initialize(node, mission, dir:)
      @node = node
      @mission = mission
      @files = Pathname(dir).join(FILES_DIR)
    end

    def run
      # Positions are unique per mission: move the existing ones out of the way, so re-ordering can't clash.
      @mission.intercepts.update_all("position = -position")
      intercepts = @node.each_item(:intercepts) { |node, index| import_intercept(node, index + 1) }
      @node.check_unique!("intercept", intercepts.map(&:key))
      @mission.intercepts.where.not(id: intercepts.map(&:id)).destroy_all
      intercepts
    end

    private
      def import_intercept(node, position)
        node.allow_only!(*KEYS)
        key = node.required(:key)
        node.error!("key must be lower_snake_case, like meeting_time") unless key.match?(KEY_FORMAT)

        solution = fictional(node, :solution, node.required(:solution))
        intercept = @mission.intercepts.find_or_initialize_by(key:)
        attributes = {
          position:, title: fictional(node, :title, node.required(:title)), source: fictional(node, :source, node.required(:source)),
          question: fictional(node, :question, node.required(:question)), solution:,
          explanation: fictional(node, :explanation, node.required(:explanation)),
          flag_digests: flags(node, solution).map { |flag| Intercept.digest(flag) },
          points: node.optional(:points, Integer, default: 100)
        }.merge(content(node, solution))
        node.saving { intercept.update!(attributes) }
        intercept
      end

      def content(node, solution)
        given = %i[ encode body file ].select { |key| node.key?(key) }
        node.error!("give exactly one of encode, body or file") unless given.one?

        case given.first
        when :encode then encoded(node, solution)
        when :body then { body: fictional(node, :body, node.required(:body)), recipe: [], file_name: nil, file_type: nil, file_data: nil }
        when :file then file(node)
        end
      end

      def encoded(node, solution)
        recipe = node.raw(:encode)
        cipher = Intercept::Cipher.new(recipe)
        body = cipher.encode(solution).force_encoding("UTF-8")
        unless body.valid_encoding? && !body.match?(/[^\P{Cntrl}\n\t]/)
          node.error!("encode leaves raw bytes the page can't show: end the recipe with to_hex, to_base64 or to_base32")
        end
        node.error!("encode doesn't decode back to the solution") unless cipher.decode(body).force_encoding("UTF-8") == solution

        { body:, recipe:, file_name: nil, file_type: nil, file_data: nil }
      rescue Intercept::Cipher::InvalidRecipe => invalid
        node.error!("encode: #{invalid.message}")
      end

      def file(node)
        name = node.required(:file)
        node.error!("file must be a plain file name, like harbour-photo.png") unless name.match?(/\A[a-z0-9][a-z0-9-]*\.[a-z]+\z/)
        type = Intercept::FILE_TYPES[File.extname(name)] or
          node.error!("file must be one of #{Intercept::FILE_TYPES.keys.join(", ")} (got #{name})")

        path = @files.join(name)
        node.error!("file #{FILES_DIR}/#{name} not found next to the mission") unless path.file?
        node.error!("file #{name} is over #{Intercept::MAX_FILE_BYTES / 1.kilobyte} KB") if path.size > Intercept::MAX_FILE_BYTES

        data = path.binread
        signature = FILE_SIGNATURES[type]
        node.error!("file #{name} isn't really a #{File.extname(name).delete(".")}") if signature && !data.start_with?(signature)
        node.error!("file #{name} isn't UTF-8 text") if type == "text/plain" && !data.dup.force_encoding("UTF-8").valid_encoding?
        # A log or a document's text is player-visible too, so it's fiction only like everything else.
        node.check_fictional!(:file, readable_text(data, type)) unless type == "image/png"

        { body: nil, recipe: [], file_name: name, file_type: type, file_data: data }
      end

      # What a player can read in a text file or a PDF: a PDF's strings and comments, not its operators
      # (whose BT, for "begin text", would read as a brand).
      def readable_text(data, type)
        return data.dup.force_encoding("UTF-8") if type == "text/plain"

        text = data.dup.force_encoding("ISO-8859-1").encode("UTF-8")
        (text.scan(/\(((?:\\.|[^\\)])*)\)/).flatten + text.scan(/^%(?!PDF-|%EOF).*$/)).join("\n")
      end

      # flag: "Fuel depot", or flags: [ "0340", "03:40" ] for answers that can be written more than one way.
      def flags(node, solution)
        node.error!("give flag or flags, not both") if node.key?(:flag) && node.key?(:flags)
        flags = node.key?(:flags) ? node.raw(:flags) : [ node.required(:flag) ]
        node.error!("flags must be a list of text") unless flags.is_a?(Array) && flags.any? && flags.all?(String)

        flags.each do |flag|
          normalised = Intercept.normalise(flag)
          node.error!("a flag can't be blank") if normalised.empty?
          unless Intercept.normalise(solution).include?(normalised)
            node.error!("flag \"#{flag}\" must appear in the solution, so the player can find it")
          end
        end
      end

      def fictional(node, key, text)
        node.check_fictional!(key, text)
      end
  end
end
