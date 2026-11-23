# frozen_string_literal: true

require "nokogiri"

module TcxKit
  module XML
    # Streams the elements of an XML document with Nokogiri's SAX parser,
    # enforcing Limits and refusing unsafe input. Knows nothing about TCX.
    #
    #   Parser.new(io, limits: Limits::DEFAULT, source_label: "run.tcx").each_event do |type, element|
    #     # type is :start or :end; element.text is set at :end
    #   end
    #
    # One pass only. Internal API: use Reader.
    class Parser < Nokogiri::XML::SAX::Document
      def initialize(io, limits:, source_label:)
        super()
        @io = io
        @limits = limits
        @source_label = source_label
        @clock = Clock.new(limits.max_seconds)
        @max_elements = limits.max_elements
        @max_depth = limits.max_depth
        @max_text_bytes = limits.max_text_bytes
      end

      # Runs a block without counting its time towards Limits#max_seconds.
      def outside(&block)
        @clock.outside(&block)
      end

      def each_event(&block)
        raise ArgumentError, "each_event needs a block" unless block
        raise Error.new("A Parser reads once", source: @source_label) if @block

        @block = block
        @clock.restart
        @source = Source.new(@io, limits: @limits, source_label: @source_label, clock: @clock)
        @stack = []
        @elements = 0
        @root_seen = false

        Nokogiri::XML::SAX::Parser.new(self).parse_io(@source) do |context|
          context.replace_entities = false
          context.recovery = false
          @context = context
        end

        raise @source.error if @source.error
        raise invalid("The document has no root element") unless @root_seen
        raise truncated("The document ended before its root element closed") unless @stack.empty?

        nil
      end

      # SAX callbacks

      NO_ATTRIBUTES = [].freeze

      # How many elements pass between clock checks.
      CLOCK_INTERVAL = 64

      def start_element_namespace(name, attrs = [], _prefix = nil, uri = nil, _namespaces = [])
        raise_source_error
        @elements += 1
        check_clock if (@elements % CLOCK_INTERVAL).zero?
        exceeded(:max_elements, "More than #{@max_elements} elements") if @max_elements && @elements > @max_elements
        depth = @stack.size + 1
        exceeded(:max_depth, "Elements nested deeper than #{@max_depth}") if @max_depth && depth > @max_depth

        attributes = attrs.empty? ? NO_ATTRIBUTES : attrs.map do |attribute|
          if @max_text_bytes && attribute.value.bytesize > @max_text_bytes
            exceeded(:max_text_bytes, "Attribute #{short(attribute.localname)} is over the #{@max_text_bytes}-byte text limit")
          end
          Attribute.new(namespace: attribute.uri, name: attribute.localname, value: attribute.value).freeze
        end.freeze

        # libxml2 reports a start tag cut off by the end of the input (as in
        # "<Trai") before failing on it. A complete start tag ends at or after
        # the reported position, so there is text after it.
        if @source.eof? && @source.tail_after(@context.line, @context.column) == ""
          raise truncated("The document ended inside the start tag of #{short(name)}")
        end

        @stack.last&.child_started!
        element = Element.new(namespace: uri, name: name, attributes: attributes,
                              line: @context.line, column: @context.column, depth: depth)
        @root_seen = true
        @stack << element
        emit(:start, element)
      end

      def end_element_namespace(_name, _prefix = nil, _uri = nil)
        raise_source_error
        element = @stack.pop
        element.finish!
        emit(:end, element)
      end

      def characters(string)
        element = @stack.last
        return unless element

        size = element.append_text(string)
        return unless @max_text_bytes && size > @max_text_bytes

        exceeded(:max_text_bytes, "Text of #{short(element.name)} is over the #{@max_text_bytes}-byte limit")
      end

      def cdata_block(string)
        characters(string)
      end

      # Nokogiri calls this for a reference to an entity declared in a DTD,
      # never for the five predefined entities or character references.
      def reference(name, _content)
        raise UnsafeContentError.new("Reference to the DTD entity #{short(name)}", **position)
      end

      def error(message)
        raise_source_error
        message = message.to_s.strip
        raise truncated(message) if cut_off?(message)

        raise invalid(message)
      end

      def warning(_message); end

      private

      # Events go straight to the block: its time counts as reading time.
      # The Reader leaves out only the time spent in its caller's block,
      # through #outside, once per message instead of once per element.
      def emit(type, element)
        @block.call(type, element)
      end

      # A file that was cut off makes libxml2 fail at the end of the input,
      # before the root element has closed, with at most part of one token
      # (a name, a value, some text) after the reported position. A malformed
      # file has markup after it. A mismatched end tag at the very end is
      # malformed too.
      def cut_off?(message)
        return false unless @source.eof? && @source.markup?
        return false if @root_seen && @stack.empty?
        return false if message.include?("mismatch")

        tail = @source.tail_after(@context.line, @context.column)
        !tail.nil? && !tail.match?(/[<>]/)
      end

      def check_clock
        return unless @clock.exceeded?

        raise LimitExceededError.new("Reading took more than #{@limits.max_seconds} s",
                                     limit: :max_seconds, **position)
      end

      def exceeded(limit, message)
        raise LimitExceededError.new(message, limit: limit, **position)
      end

      def raise_source_error
        raise @source.error if @source.error
      end

      def invalid(message)
        InvalidFileError.new(message, **position)
      end

      def truncated(message)
        TruncatedFileError.new(message, **position)
      end

      def position
        { source: @source_label, line: @context&.line, column: @context&.column }
      end

      def short(name)
        name.to_s.length > 64 ? "#{name.to_s[0, 64]}..." : name.to_s
      end
    end
  end
end
