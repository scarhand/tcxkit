# frozen_string_literal: true

module TcxKit
  # Decodes the text of a field by its XSD type. Never raises: text that does
  # not fit the type gives a nil value and a reason.
  module Types
    # A field's type: name (as Field#type reports it), the decoder, and the
    # range or enumeration it is restricted to.
    # preserve: keep whitespace (an enumeration based on xsd:string) instead
    # of collapsing it. min_length, max_length and pattern restrict a token
    # (XSD minLength, maxLength or length, and pattern), in characters.
    Spec = Struct.new(:name, :decoder, :min, :max, :max_exclusive, :values, :signed, :preserve,
                      :min_length, :max_length, :pattern, keyword_init: true) do
      def known?
        name != :unknown
      end
    end

    DOUBLE = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/
    DECIMAL = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)\z/
    SIGNED_INTEGER = /\A[+-]?\d+\z/
    NON_FINITE_DOUBLES = %w[INF +INF -INF NaN].freeze
    # The XSD 1.1 lexical rule for unsigned types: an optional "+", and "-"
    # only before zero. XSD 1.0 allows digits only; the value is the same
    # either way, so the more lenient rule is kept (SPECIFICATION.md 6.3).
    UNSIGNED_INTEGER = /\A(?:\+?\d+|-0+)\z/
    G_YEAR = /\A(-?\d{4,})(Z|[+-]\d{2}:\d{2})?\z/
    DATE_TIME = /\A(-?\d{4,})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)(Z|[+-]\d{2}:\d{2})?\z/
    BOOLEANS = { "true" => true, "1" => true, "false" => false, "0" => false }.freeze
    DAYS_IN_MONTH = [nil, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

    module_function

    def string(name = :string) = Spec.new(name: name, decoder: :string)
    def token(name = :token, min_length: nil, max_length: nil, length: nil, pattern: nil)
      Spec.new(name: name, decoder: :token, min_length: length || min_length, max_length: length || max_length,
               pattern: pattern && Regexp.new("\\A(?:#{pattern})\\z"))
    end
    def g_year = Spec.new(name: :g_year, decoder: :g_year)
    def double(name = :double, min: nil, max: nil, max_exclusive: nil)
      Spec.new(name: name, decoder: :double, min: min, max: max, max_exclusive: max_exclusive)
    end
    def decimal(name = :decimal, min: nil, max: nil, max_exclusive: nil)
      Spec.new(name: name, decoder: :decimal, min: min, max: max, max_exclusive: max_exclusive)
    end
    def integer(name, min:, max:, signed: false) = Spec.new(name: name, decoder: :integer, min: min, max: max, signed: signed)
    def date_time = Spec.new(name: :date_time, decoder: :date_time)
    def boolean = Spec.new(name: :boolean, decoder: :boolean)

    # values: the schema's enumeration, mapped to symbols in snake_case.
    def enumeration(name, values, preserve: false)
      Spec.new(name: name, decoder: :enumeration, preserve: preserve,
               values: values.to_h { |value| [value, Naming.snake_case(value).to_sym] })
    end

    UNKNOWN = Spec.new(name: :unknown, decoder: :string).freeze

    # [raw_value, value, invalid_reason] for text as written. raw_value is the
    # text after the type's whitespace rule: kept for strings, collapsed for
    # everything else (XSD whiteSpace "collapse").
    def decode(spec, text)
      return [text, text, nil] if spec.decoder == :string

      raw = spec.preserve ? text : collapse(text)
      return decode_token(spec, raw) if spec.decoder == :token
      return [raw, nil, :empty] if raw.empty?

      value, reason =
        case spec.decoder
        when :double then decode_double(spec, raw)
        when :decimal then decode_decimal(spec, raw)
        when :integer then decode_integer(spec, raw)
        when :date_time then decode_date_time(spec, raw)
        when :enumeration then decode_enumeration(spec, raw)
        when :boolean then decode_boolean(spec, raw)
        when :g_year then decode_g_year(spec, raw)
        end
      [raw, reason ? nil : value, reason]
    end

    WHITESPACE = /[ \t\r\n]/

    def collapse(text)
      return text unless text.match?(WHITESPACE)

      text.gsub(/[ \t\r\n]+/, " ").strip
    end

    def decode_double(spec, raw)
      return [nil, :not_finite] if NON_FINITE_DOUBLES.include?(raw)
      return [nil, :not_a_number] unless DOUBLE.match?(raw)

      value = Float(raw)
      return [nil, :not_finite] unless value.finite?

      [value, range_reason(spec, value)]
    end

    # A token, checked against its length and pattern facets.
    def decode_token(spec, raw)
      reason =
        if spec.min_length && raw.length < spec.min_length then :too_short
        elsif spec.max_length && raw.length > spec.max_length then :too_long
        elsif spec.pattern && !spec.pattern.match?(raw) then :no_pattern_match
        end
      [raw, reason ? nil : raw, reason]
    end

    # xsd:gYear: the year as an Integer; a time zone, if written, stays in
    # the raw value.
    def decode_g_year(_spec, raw)
      match = G_YEAR.match(raw)
      return [nil, :not_a_year] unless match
      return [nil, :not_a_year] if match[2] && !valid_zone?(match[2])

      [Integer(match[1], 10), nil]
    end

    # xsd:decimal: no exponent, no INF or NaN.
    def decode_decimal(spec, raw)
      return [nil, :not_a_number] unless DECIMAL.match?(raw)

      value = Float(raw)
      [value, range_reason(spec, value)]
    end

    def decode_integer(spec, raw)
      return [nil, :not_an_integer] unless (spec.signed ? SIGNED_INTEGER : UNSIGNED_INTEGER).match?(raw)

      value = Integer(raw.delete_prefix("+"), 10)
      [value, range_reason(spec, value)]
    end

    def decode_enumeration(spec, raw)
      value = spec.values[raw]
      [value, value.nil? ? :not_in_enumeration : nil]
    end

    def decode_boolean(_spec, raw)
      [BOOLEANS[raw], BOOLEANS.key?(raw) ? nil : :not_a_boolean]
    end

    # A Time in UTC. Text without a UTC offset has no value (decision 1):
    # its time zone is unknown and is never guessed.
    def decode_date_time(_spec, raw)
      match = DATE_TIME.match(raw)
      return [nil, :not_a_date_time] unless match

      year, month, day, hour, minute = match[1..5].map { |part| Integer(part, 10) }
      second = match[6].include?(".") ? Rational(match[6]) : Integer(match[6], 10)
      zone = match[7]
      return [nil, :not_a_date_time] unless valid_date_time?(year, month, day, hour, minute, second, zone)
      return [nil, :no_utc_offset] unless zone

      offset = zone == "Z" ? "+00:00" : zone
      [Time.new(year, month, day, hour, minute, second, offset).utc, nil]
    end

    def valid_date_time?(year, month, day, hour, minute, second, zone)
      return false unless (1..12).cover?(month) && day.between?(1, days_in_month(year, month))
      return false unless hour.between?(0, 23) && minute.between?(0, 59) && second < 60
      zone.nil? || valid_zone?(zone)
    end

    def valid_zone?(zone)
      return true if zone == "Z"

      zone_hours, zone_minutes = zone[1..].split(":").map { |part| Integer(part, 10) }
      zone_minutes <= 59 && (zone_hours * 60 + zone_minutes) <= 14 * 60
    end

    def days_in_month(year, month)
      return 29 if month == 2 && (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)

      DAYS_IN_MONTH[month]
    end

    def range_reason(spec, value)
      return :out_of_range if spec.min && value < spec.min
      return :out_of_range if spec.max && value > spec.max
      return :out_of_range if spec.max_exclusive && value >= spec.max_exclusive

      nil
    end
  end

  module Naming
    module_function

    CACHE_SIZE = 4096
    @cache = {}

    # "HeartRateBpm" => "heart_rate_bpm", "ProductID" => "product_id".
    # Cached, since the same few names repeat on every trackpoint; the cache
    # is bounded because unknown names come from the file.
    def snake_case(name)
      cache = Naming.instance_variable_get(:@cache)
      cached = cache[name]
      return cached if cached

      converted = convert(name).freeze
      cache[name.dup.freeze] = converted if cache.size < CACHE_SIZE
      converted
    end

    def convert(name)
      name.to_s
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("- ", "__")
          .downcase
    end
  end
end
