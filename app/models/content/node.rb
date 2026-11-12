module Content
  # A hash from a YAML file plus where it came from, so every error can name its exact location,
  # e.g. "content/tracks/basics/month-end.yml: messages[1] (fake_invoice) → links[0]: …".
  class Node
    BOOLEAN = :boolean

    attr_reader :file, :path

    def self.load_file(pathname, root:)
      relative = Pathname(pathname).relative_path_from(Pathname(root).parent).to_s
      data = YAML.safe_load_file(pathname, aliases: false)
      raise ImportError.new("expected a mapping of keys to values at the top level", file: relative) unless data.is_a?(Hash)

      new(data, file: relative)
    rescue Psych::Exception => error
      raise ImportError.new("isn't valid YAML (#{error.message})", file: relative)
    end

    def initialize(data, file:, path: [])
      @data = data
      @file = file
      @path = path
    end

    def allow_only!(*keys)
      unknown = @data.keys.map(&:to_s) - keys.map(&:to_s)
      error!("unknown #{"key".pluralize(unknown.size)} #{unknown.join(", ")} (allowed: #{keys.join(", ")})") if unknown.any?
    end

    def key?(key)
      @data.key?(key.to_s)
    end

    def required(key, type = String)
      error!("#{key} is required") if blank_value?(@data[key.to_s])
      typed(key, type)
    end

    def optional(key, type = String, default: nil)
      blank_value?(@data[key.to_s]) ? default : typed(key, type)
    end

    # Yields a Node for each item in a list, labelled with its index and (if present) its key.
    def each_item(key, required: true)
      items = @data[key.to_s]
      return [] if !required && (items.nil? || items == [])

      error!("#{key} must be a list with at least one item") unless items.is_a?(Array) && items.any?
      items.each_with_index.map do |item, index|
        label = "#{key}[#{index}]"
        label += " (#{item["key"]})" if item.is_a?(Hash) && item["key"].is_a?(String)
        error!("must be a mapping of keys to values", path: path + [ label ]) unless item.is_a?(Hash)

        yield Node.new(item, file:, path: path + [ label ]), index
      end
    end

    def error!(message, path: self.path)
      raise ImportError.new(message, file:, location: path.join(" → "))
    end

    # Runs a block and reports any model validation failure at this node's location.
    def saving
      yield
    rescue ActiveRecord::RecordInvalid => invalid
      error!("#{invalid.record.class.name.underscore.humanize} is invalid: #{invalid.record.errors.full_messages.to_sentence}")
    end

    private
      def typed(key, type)
        value = @data[key.to_s]
        valid = case type
        when BOOLEAN then value == true || value == false
        when Integer then value.is_a?(Integer)
        else value.is_a?(type)
        end
        error!("#{key} must be #{type == BOOLEAN ? "true or false" : "a #{type.name.downcase}"} (got #{value.inspect})") unless valid

        value.is_a?(String) ? value.strip : value
      end

      def blank_value?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
      end
  end
end
