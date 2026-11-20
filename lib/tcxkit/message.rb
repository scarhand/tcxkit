# frozen_string_literal: true

module TcxKit
  # One meaningful TCX element, emitted when it closes (SPECIFICATION.md 6.2).
  #
  #   message.name          # :trackpoint, :lap, :activity, ... or :element
  #   message.element_name  # the XML element's local name, e.g. "Trackpoint"
  #   message.context       # { activity: 0, lap: 2, track: 0, trackpoint: 41 }
  #   message.line, message.column
  #   message.fields        # every Field, in document order; names can repeat
  #   message[:heart_rate_bpm]      # value of the first field with that name
  #   message["HeartRateBpm/Value"] # value of the field at that path
  class Message
    attr_reader :name, :element_name, :namespace, :context, :line, :column, :fields

    def initialize(name:, element_name:, namespace:, context:, line:, column:, fields:)
      @name = name
      @element_name = element_name
      @namespace = namespace
      @context = context
      @line = line
      @column = column
      @fields = fields.freeze
      freeze
    end

    # The typed value of a field, by name (Symbol) or path (String).
    def [](key)
      field(key)&.value
    end

    def field(key)
      case key
      when Symbol then @fields.find { |field| field.name == key }
      when String then @fields.find { |field| field.path == key }
      else raise ArgumentError, "field lookup takes a name (Symbol) or a path (String)"
      end
    end

    def fields_named(name)
      @fields.select { |field| field.name == name.to_sym }
    end

    # Fields for the attributes of the message element itself.
    def attributes
      @fields.select { |field| field.path.start_with?("@") }
    end

    # The Time field of a trackpoint or course point, else nil.
    def timestamp
      self[:time]
    end

    # Name => value, for the first field of each name.
    def to_h
      @fields.each_with_object({}) { |field, hash| hash[field.name] = field.value unless hash.key?(field.name) }
    end

    def inspect
      "#<#{self.class.name} #{name} #{context.inspect} #{fields.size} fields>"
    end
  end
end
