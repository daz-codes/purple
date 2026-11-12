module Content
  # Raised for any problem in authored content. The message always says which file and where.
  class ImportError < StandardError
    attr_reader :file, :location

    def initialize(message, file: nil, location: nil)
      @file = file
      @location = location
      super([ file, location.presence, message ].compact.join(": "))
    end
  end
end
