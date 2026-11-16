# The authored content used to judge a finished Blue attempt. Stored as JSON, with explicit record
# types when read back; no classes or executable values come from the stored data. Copies are read-only.
#
# A copy outlives the schema it was taken under. When read back, attributes for columns that have since
# been removed are dropped, and columns added since take their defaults, so old copies keep loading. A
# migration that renames a column or changes what one means must also rewrite result_content.
class ShiftAttempt::ContentSnapshot
  def self.capture(shift)
    shift.as_json(include: {
      track: {}, hints: {}, messages: { include: { links: {}, red_flags: {}, techniques: {} } }
    })
  end

  def initialize(attributes)
    @attributes = attributes
  end

  def shift
    @shift ||= begin
      shift = record(Shift, @attributes.except("messages", "hints", "track"))
      associate(shift, :track, record(Track, @attributes.fetch("track")))
      associate(shift, :hints, @attributes.fetch("hints").map { |attributes| record(Hint, attributes) })
      messages = @attributes.fetch("messages").map do |attributes|
        message = record(Message, attributes.except("links", "red_flags", "techniques"))
        associate(message, :shift, shift)
        { links: Link, red_flags: RedFlag, techniques: Technique }.each do |name, type|
          children = attributes.fetch(name.to_s).map do |child_attributes|
            child = record(type, child_attributes)
            associate(child, :message, message) unless type == Technique
            child
          end
          associate(message, name, children)
        end
        message
      end
      associate(shift, :messages, messages)
      shift
    end
  end

  private
    def record(type, attributes)
      type.instantiate(type.column_defaults.merge(attributes.slice(*type.column_names))).tap(&:readonly!)
    end

    def associate(record, name, target)
      record.association(name).tap do |association|
        association.target = target
        association.loaded!
      end
    end
end
