# frozen_string_literal: true

module TcxKit
  # Bounds on what one pass of a Reader will read, enforced while reading.
  #
  # The reader runs inside the caller's process and cannot be stopped safely
  # from outside, so it checks its own limits and raises LimitExceededError as
  # soon as one is crossed:
  #
  # - max_bytes:      bytes read from the source.
  # - max_elements:   XML elements opened.
  # - max_depth:      element nesting; the root element is depth 1.
  # - max_text_bytes: the text of one element, the value of one attribute, or
  #                   the prolog before the root element.
  # - max_seconds:    time spent reading, on a monotonic clock. Time spent in
  #                   the caller's block is not counted.
  #
  # nil switches a limit off.
  class Limits
    attr_reader :max_bytes, :max_elements, :max_depth, :max_text_bytes, :max_seconds

    def initialize(max_bytes: 64 * 1024 * 1024, max_elements: 5_000_000, max_depth: 64,
                   max_text_bytes: 1024 * 1024, max_seconds: nil)
      @max_bytes = positive(:max_bytes, max_bytes)
      @max_elements = positive(:max_elements, max_elements)
      @max_depth = positive(:max_depth, max_depth)
      @max_text_bytes = positive(:max_text_bytes, max_text_bytes)
      @max_seconds = positive(:max_seconds, max_seconds)
      freeze
    end

    def self.none
      new(max_bytes: nil, max_elements: nil, max_depth: nil, max_text_bytes: nil, max_seconds: nil)
    end

    # A Limits, or a Hash of its keywords (missing keys keep their defaults).
    def self.coerce(value)
      case value
      when Limits then value
      when Hash then new(**value)
      else raise ArgumentError, "limits must be a #{name} or a Hash"
      end
    end

    def to_h
      { max_bytes: max_bytes, max_elements: max_elements, max_depth: max_depth,
        max_text_bytes: max_text_bytes, max_seconds: max_seconds }
    end

    private

    def positive(name, value)
      return nil if value.nil?
      raise ArgumentError, "#{name} must be a positive number or nil" unless value.is_a?(Numeric) && value.positive?

      value
    end
  end

  # 64 MB, 5 million elements, depth 64, 1 MB of text per element, no time
  # limit: generous for any real activity file.
  Limits::DEFAULT = Limits.new
end
