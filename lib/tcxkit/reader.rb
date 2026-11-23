# frozen_string_literal: true

module TcxKit
  # Streams the messages of a TCX v2 document.
  #
  #   TcxKit::Reader.new("activity.tcx").each_message { |message| ... }
  #
  # source is a path, a Pathname or an IO-like object that responds to read.
  # Caller-owned IO is closed only with close_io: true. A seekable IO is read
  # from its position at construction on every pass; a non-seekable one can
  # be read once.
  #
  # limits: a TcxKit::Limits, or a Hash of its keywords. Limits::DEFAULT
  # unless given; Limits.none switches them off.
  #
  # Each message is yielded when its element closes, so a lap's trackpoints
  # come before the lap and an activity's laps before the activity; the
  # last message is :document. See Message and SPECIFICATION.md 6.2.
  class Reader
    attr_reader :source_label, :limits

    def initialize(source, close_io: false, source_label: nil, limits: Limits::DEFAULT)
      @close_io = close_io
      @limits = Limits.coerce(limits)
      @consumed = false
      @closed_by_reader = false

      # Pathname responds to read (it reads the whole file), so paths come first.
      if source.is_a?(String) || source.is_a?(Pathname)
        @path = source.to_s
        @source_label = source_label || @path
      elsif source.respond_to?(:read)
        @io = source
        @source_label = source_label || (source.respond_to?(:path) ? source.path : source.class.name)
        @initial_position = initial_position(source)
        raise ArgumentError, "close_io requires a closeable IO-like source" if @close_io && !source.respond_to?(:close)
      elsif source.respond_to?(:to_path)
        @path = source.to_path
        @source_label = source_label || @path
      else
        raise ArgumentError, "source must be a filesystem path or an IO-like object"
      end
    end

    def each_message(&block)
      return enum_for(__method__) unless block

      io, owned = open_io
      begin
        parser = XML::Parser.new(io, limits: @limits, source_label: @source_label)
        builder = MessageBuilder.new { |message| parser.outside { block.call(message) } }
        parser.each_event do |type, element|
          check_root(element) if type == :start && element.depth == 1
          builder.handle(type, element)
        end
      ensure
        @closed_by_reader = true if @close_io && @io.equal?(io)
        io.close if (owned || @close_io) && io.respond_to?(:close) && !(io.respond_to?(:closed?) && io.closed?)
      end
      nil
    end

    private

    def check_root(element)
      unless element.name == "TrainingCenterDatabase"
        raise UnsupportedFormatError.new("The root element is #{short(element.name)}, not TrainingCenterDatabase",
                                         source: @source_label, line: element.line, column: element.column)
      end
      return if element.namespace == NAMESPACE

      message =
        if element.namespace == NAMESPACE_V1 then "TCX v1 is not supported"
        else "TrainingCenterDatabase is not in the TCX v2 namespace"
        end
      raise UnsupportedFormatError.new(message, source: @source_label, line: element.line, column: element.column)
    end

    def short(name)
      name.length > 64 ? "#{name[0, 64]}..." : name
    end

    def initial_position(io)
      return unless io.respond_to?(:pos) && io.respond_to?(:seek)

      io.pos
    rescue IOError, Errno::ESPIPE
      nil
    end

    def open_io
      return [File.open(@path, "rb"), true] if @path

      if @closed_by_reader || (@io.respond_to?(:closed?) && @io.closed?)
        raise Error.new("The IO source is closed", source: @source_label)
      end

      if @initial_position
        @io.seek(@initial_position)
      elsif @consumed
        raise Error.new("A non-seekable IO source can only be read once", source: @source_label)
      else
        @consumed = true
      end
      [@io, false]
    end
  end
end
