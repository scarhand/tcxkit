# frozen_string_literal: true

module TcxKit
  # One value inside a Message: a leaf element or an attribute.
  #
  #   field.name           # :heart_rate_bpm
  #   field.path           # "HeartRateBpm/Value", relative to the message element
  #   field.namespace      # namespace URI of the element or attribute (nil for none)
  #   field.text           # the text exactly as written
  #   field.raw_value      # the text after the type's whitespace rule
  #   field.value          # typed value, nil when invalid
  #   field.type           # :positive_byte, :double, :date_time, :sport, :string, :unknown, ...
  #   field.known?         # false for elements and attributes the schema does not put here
  #   field.valid?
  #   field.invalid_reason # nil, :empty, :not_a_number, :not_finite, :not_an_integer,
  #                        # :out_of_range, :not_a_date_time, :no_utc_offset,
  #                        # :not_in_enumeration, :not_a_boolean, :not_a_year,
  #                        # :too_short, :too_long, :no_pattern_match
  #   field.line
  class Field
    attr_reader :name, :path, :namespace, :text, :raw_value, :value, :type, :invalid_reason, :line

    def initialize(name:, path:, namespace:, text:, spec:, line:)
      @name = name
      @path = path
      @namespace = namespace
      @text = text
      @type = spec.name
      @known = spec.known?
      @raw_value, @value, @invalid_reason = Types.decode(spec, text)
      @line = line
      freeze
    end

    def known?
      @known
    end

    def valid?
      @invalid_reason.nil?
    end

    def attribute?
      @path.split("/").last.start_with?("@")
    end

    def inspect
      "#<#{self.class.name} #{path}=#{raw_value.inspect}#{valid? ? '' : " invalid: #{invalid_reason}"}>"
    end
  end
end
