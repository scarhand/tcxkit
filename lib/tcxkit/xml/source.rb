# frozen_string_literal: true

module TcxKit
  module XML
    # The IO that Nokogiri reads from. It
    #
    # - counts bytes for Limits#max_bytes,
    # - checks the prolog (everything before the root element) and refuses a
    #   DTD internal subset, which is where entities are declared,
    # - skips whitespace before the XML declaration (SPECIFICATION.md,
    #   section 7), keeping a byte order mark,
    # - keeps the line count and the end of the last line, so the Parser can
    #   tell a file that was cut off from one that is malformed (#tail_after).
    #
    # Nokogiri swallows exceptions raised in #read, so a refusal is kept in
    # #error and #read reports the end of input; the Parser raises it.
    class Source
      CHUNK_SIZE = 64 * 1024
      TAIL_WINDOW = 4096
      CONTINUATION_BYTES = "\x80-\xBF".b.freeze
      BOM = "\xEF\xBB\xBF".b.freeze

      attr_reader :error, :lines

      def initialize(io, limits:, source_label:, clock:)
        @io = io
        @limits = limits
        @source_label = source_label
        @clock = clock
        @bytes = 0
        @pending = nil
        @eof = false
        @error = nil
        @lines = 1
        @last_line = +"".b
        @last_line_chars = 0
        @delivered = false
        @markup = false
      end

      # True once the underlying IO has reported its end and everything read
      # has been handed on.
      def eof?
        @eof && (@pending.nil? || @pending.empty?)
      end

      # The text handed on after a position libxml2 reported (1-based line,
      # 1-based column in characters), or nil when the position is not on
      # the last line or too far from its end to tell.
      def tail_after(line, column)
        return "" if line > @lines
        return nil if line < @lines

        length = @last_line_chars - (column - 1)
        return "" if length <= 0

        window = @last_line.dup.force_encoding(Encoding::UTF_8).scrub
        length > window.length ? nil : window[-length..]
      end

      # True once any byte has been handed to the XML parser.
      def delivered?
        @delivered
      end

      # True when the input handed on starts like XML: "<", after an optional
      # byte order mark.
      def markup?
        @markup
      end

      def read(length, _buffer = nil)
        return nil if @error
        return refuse(time_limit_error) if @clock.exceeded?

        @pending ||= prefix
        return nil if @error

        data = @pending.empty? ? read_raw(length) : take(length)
        return nil if data.nil? || @error

        unless @delivered
          @delivered = true
          @markup = data.byteslice(data.start_with?(BOM) ? BOM.bytesize : 0, 1) == "<"
        end
        count_lines(data)
        data
      end

      private

      def read_raw(length)
        return nil if @eof

        data = @io.read(length)
        if data.nil? || data.empty?
          @eof = true
          return nil
        end

        @bytes += data.bytesize
        max = @limits.max_bytes
        if max && @bytes > max
          return refuse(LimitExceededError.new("The input is over the #{max}-byte limit",
                                               limit: :max_bytes, source: @source_label))
        end

        data.b
      end

      # Reads until the prolog is complete and returns what was read, minus
      # whitespace before the XML declaration.
      def prefix
        buffer = +"".b
        loop do
          chunk = read_raw(CHUNK_SIZE)
          return +"".b if @error

          buffer << chunk if chunk
          result = Prolog.scan(buffer, complete: chunk.nil?)
          if result == :unsafe
            refuse(UnsafeContentError.new("The document declares a DTD internal subset", source: @source_label))
            return +"".b
          end

          max = @limits.max_text_bytes
          if max && (result == :more ? buffer.bytesize : result) > max
            refuse(LimitExceededError.new("The prolog is over the #{max}-byte text limit",
                                          limit: :max_text_bytes, source: @source_label))
            return +"".b
          end
          return without_leading_whitespace(buffer) unless result == :more
        end
      end

      def without_leading_whitespace(buffer)
        bom = buffer.start_with?(BOM)
        body = bom ? buffer.byteslice(BOM.bytesize..) : buffer
        body = body.sub(/\A[ \t\r\n]+/n, "")
        bom ? BOM + body : body
      end

      def take(length)
        data = @pending.byteslice(0, length)
        @pending = @pending.byteslice(length..) || +"".b
        data
      end

      def count_lines(data)
        newline = data.rindex("\n")
        if newline
          @lines += data.count("\n")
          part = data.byteslice((newline + 1)..)
          @last_line = +"".b
          @last_line_chars = 0
        else
          part = data
        end
        @last_line << part
        @last_line = @last_line.byteslice(-TAIL_WINDOW..) if @last_line.bytesize > TAIL_WINDOW
        @last_line_chars += part.bytesize - part.count(CONTINUATION_BYTES)
      end

      def time_limit_error
        LimitExceededError.new("Reading took more than #{@limits.max_seconds} s",
                               limit: :max_seconds, source: @source_label)
      end

      def refuse(error)
        @error ||= error
        nil
      end
    end

    # Scans the prolog: an optional byte order mark, whitespace, the XML
    # declaration, processing instructions, comments and a document type
    # declaration, up to the root element's start tag.
    module Prolog
      WHITESPACE = [0x20, 0x09, 0x0D, 0x0A].freeze
      PI_START = "<?".b.freeze
      PI_END = "?>".b.freeze
      COMMENT_START = "<!--".b.freeze
      COMMENT_END = "-->".b.freeze
      DOCTYPE = "<!DOCTYPE".b.freeze
      MARKUP_STARTS = [PI_START, COMMENT_START, DOCTYPE].freeze

      module_function

      # The byte position where the prolog ends (at the root element, or at
      # anything that is not prolog), :more when more input is needed to
      # decide, or :unsafe for a DTD internal subset. With complete: true
      # there is no more input, and anything unfinished is left for the XML
      # parser to report.
      def scan(buffer, complete:)
        utf16 = utf16(buffer)
        return scan(utf16, complete: complete) if utf16

        position = buffer.start_with?(Source::BOM) ? Source::BOM.bytesize : 0
        loop do
          position += 1 while position < buffer.bytesize && WHITESPACE.include?(buffer.getbyte(position))
          rest = buffer.byteslice(position, DOCTYPE.bytesize) || "".b
          return complete ? position : :more if rest.empty?
          return position unless rest.getbyte(0) == 0x3C # "<"

          finish =
            if rest.start_with?(PI_START) then after(buffer, PI_END, position + 2)
            elsif rest.start_with?(COMMENT_START) then after(buffer, COMMENT_END, position + 4)
            elsif rest.start_with?(DOCTYPE) then after_doctype(buffer, position + DOCTYPE.bytesize)
            elsif !complete && MARKUP_STARTS.any? { |start| start.start_with?(rest) } then nil
            else return position
            end
          return :unsafe if finish == :unsafe
          return complete ? position : :more if finish.nil?

          position = finish
        end
      end

      UTF16_LE_BOM = "\xFF\xFE".b.freeze
      UTF16_BE_BOM = "\xFE\xFF".b.freeze
      UTF32_LE_BOM = "\xFF\xFE\x00\x00".b.freeze

      # A UTF-8 copy of a UTF-16 buffer (by its byte order mark, or by "<"
      # followed or preceded by a zero byte), so a DTD in a UTF-16 document
      # is found too; nil for any other buffer. libxml2 still reads the
      # original bytes.
      def utf16(buffer)
        encoding =
          if buffer.start_with?(UTF32_LE_BOM) then nil
          elsif buffer.start_with?(UTF16_LE_BOM) || buffer.start_with?("<\x00".b) then Encoding::UTF_16LE
          elsif buffer.start_with?(UTF16_BE_BOM) || buffer.start_with?("\x00<".b) then Encoding::UTF_16BE
          end
        return unless encoding

        units = buffer.byteslice(0, buffer.bytesize & ~1)
        units = units.byteslice(2..) if units.start_with?(UTF16_LE_BOM) || units.start_with?(UTF16_BE_BOM)
        units.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace).b
      end

      def after(buffer, terminator, from)
        found = buffer.index(terminator, from)
        found && found + terminator.bytesize
      end

      # The position after the declaration's ">", nil if it is not complete,
      # or :unsafe when it has an internal subset ("[" outside quotes).
      def after_doctype(buffer, from)
        quote = nil
        (from...buffer.bytesize).each do |position|
          byte = buffer.getbyte(position)
          if quote
            quote = nil if byte == quote
          elsif byte == 0x22 || byte == 0x27 # " or '
            quote = byte
          elsif byte == 0x5B # [
            return :unsafe
          elsif byte == 0x3E # >
            return position + 1
          end
        end
        nil
      end
    end
  end
end
