# frozen_string_literal: true

module TcxKit
  # Base for every error the reader raises. `source` labels the input;
  # `line` and `column` point at the place in the XML, when known.
  class Error < StandardError
    attr_reader :source, :line, :column

    def initialize(message, source: nil, line: nil, column: nil)
      @source = source
      @line = line
      @column = column

      context = []
      context << source if source
      context << "line #{line}" if line
      context << "column #{column}" if column
      super(context.empty? ? message : "#{message} (#{context.join(', ')})")
    end
  end

  # Not well-formed XML.
  class InvalidFileError < Error; end
  # Well-formed XML, but not a document this gem reads.
  class UnsupportedFormatError < Error; end
  # The input ended before the root element closed.
  class TruncatedFileError < Error; end
  # A construct refused for safety, such as an entity declared in a DTD.
  class UnsafeContentError < Error; end

  # A Limits bound was crossed; `limit` names it.
  class LimitExceededError < Error
    attr_reader :limit

    def initialize(message, limit:, **context)
      @limit = limit
      super(message, **context)
    end
  end
end
