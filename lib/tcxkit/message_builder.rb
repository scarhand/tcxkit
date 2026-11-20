# frozen_string_literal: true

module TcxKit
  # Turns the XML layer's element events into Messages (SPECIFICATION.md
  # 6.2). A message is emitted when its element closes; every leaf element
  # and attribute inside it, outside nested messages, becomes one of its
  # Fields. One builder per pass.
  class MessageBuilder
    XSI_NAMESPACE = "http://www.w3.org/2001/XMLSchema-instance"

    # Elements that are neither messages nor fields, by parent.
    ROOT_CONTAINERS = %w[Activities Courses].freeze
    SESSION_CONTAINERS = %w[FirstSport NextSport].freeze

    # Schema keys of the Activity Extension v2 elements.
    AX2_SEGMENTS = %w[TPX LX Speed RunCadence Watts AvgSpeed MaxBikeCadence AvgRunCadence MaxRunCadence Steps
                      AvgWatts MaxWatts Extensions].to_h { |name| [name, "ax2:#{name}".freeze] }.freeze

    # Indexes counted across the document; the others count within their parent.
    DOCUMENT_COUNTERS = %i[activity multi_sport_session course author element].freeze

    # path: the element's path inside its message ("" for the message
    # element), key: the same path in Schema terms, nil once a segment is
    # outside the schema's namespaces, name: the field name of a leaf.
    Node = Struct.new(:kind, :element, :frame, :path, :key, :name)

    # A message being collected.
    class Frame
      attr_reader :kind, :element, :context, :fields, :table

      def initialize(kind, element, context, table)
        @kind = kind
        @element = element
        @context = context.freeze
        @table = table
        @fields = []
        @counters = Hash.new(0)
      end

      def next_index(kind)
        index = @counters[kind]
        @counters[kind] += 1
        index
      end

      def to_message
        Message.new(name: kind, element_name: element.name, namespace: element.namespace, context: context,
                    line: element.line, column: element.column, fields: fields)
      end
    end

    # Paths repeat on every trackpoint, so joined paths are cached; the
    # cache is bounded because unknown element names come from the file.
    PATH_CACHE_SIZE = 4096

    def initialize(&emit)
      @emit = emit
      @nodes = []
      @counters = Hash.new(0)
      @paths = {}
    end

    def handle(type, element)
      type == :start ? start(element) : finish(element)
    end

    private

    def start(element)
      parent = @nodes.last
      return @nodes << Node.new(:root, element, nil, "", "") unless parent

      kind = message_kind(element, parent)
      if kind
        @nodes << open_message(kind, element, parent.frame)
      elsif container?(element, parent)
        @nodes << Node.new(:container, element, parent.frame, "", "")
      elsif parent.frame
        node = Node.new(:field, element, parent.frame, join(parent.path, element.name),
                        join_key(parent.key, segment(element)), field_name(parent, element))
        add_attributes(node)
        @nodes << node
      else
        @nodes << open_message(:element, element, nil)
      end
    end

    def finish(element)
      node = @nodes.pop
      case node.kind
      when :message then @emit.call(node.frame.to_message)
      when :field then add_text(node, element) unless element.children?
      when :root then @emit.call(document_message(element))
      end
    end

    def open_message(kind, element, parent_frame)
      index = DOCUMENT_COUNTERS.include?(kind) ? next_document_index(kind) : parent_frame.next_index(kind)
      context = (parent_frame ? parent_frame.context : {}).merge(kind => index)
      frame = Frame.new(kind, element, context, Schema.table(kind, context))
      node = Node.new(:message, element, frame, "", "")
      add_attributes(node)
      node
    end

    def join(path, segment)
      return segment if path.empty?

      by_segment = @paths[path] ||= {}
      cached = by_segment[segment]
      return cached if cached

      joined = "#{path}/#{segment}".freeze
      by_segment[segment] = joined if @paths.size < PATH_CACHE_SIZE && by_segment.size < PATH_CACHE_SIZE
      joined
    end

    def join_key(key, segment)
      key && segment && join(key, segment)
    end

    def next_document_index(kind)
      index = @counters[kind]
      @counters[kind] += 1
      index
    end

    # Which message an element starts, if any (only TCX v2 elements, where
    # the schema puts them).
    def message_kind(element, parent)
      return nil unless element.namespace == NAMESPACE

      parent_kind = parent.kind == :message ? parent.frame.kind : nil
      parent_container = parent.kind == :container ? parent.element.name : nil

      case element.name
      when "Activity" then :activity if %w[Activities FirstSport NextSport].include?(parent_container)
      when "MultiSportSession" then :multi_sport_session if parent_container == "Activities"
      when "Transition" then :transition if parent_container == "NextSport"
      when "Lap" then :lap if %i[activity course].include?(parent_kind)
      when "Track" then :track if %i[lap transition course].include?(parent_kind)
      when "Trackpoint" then :trackpoint if parent_kind == :track
      when "Creator" then :creator if %i[activity course].include?(parent_kind)
      when "Author" then :author if parent.kind == :root
      when "Course" then :course if parent_container == "Courses"
      when "CoursePoint" then :course_point if parent_kind == :course
      end
    end

    def container?(element, parent)
      return false unless element.namespace == NAMESPACE

      case parent.kind
      when :root then ROOT_CONTAINERS.include?(element.name)
      when :message then parent.frame.kind == :multi_sport_session && SESSION_CONTAINERS.include?(element.name)
      else false
      end
    end

    def add_attributes(node)
      node.element.attributes.each do |attribute|
        add_field(node.frame, path: join(node.path, "@#{attribute.name}"), key: join_key(node.key, attribute_segment(attribute)),
                              name: Naming.snake_case(attribute.name).to_sym, namespace: attribute.namespace,
                              text: attribute.value, line: node.element.line)
      end
    end

    def add_text(node, element)
      return if element.name == "Extensions" && element.text.strip.empty?

      add_field(node.frame, path: node.path, key: node.key, name: node.name,
                            namespace: element.namespace, text: element.text, line: element.line)
    end

    def add_field(frame, path:, key:, name:, namespace:, text:, line:)
      spec = key && frame.table[key]
      frame.fields << Field.new(name: name, path: path, namespace: namespace, text: text,
                                spec: spec || Types::UNKNOWN, line: line)
    end

    # The element's name in snake_case; a Value element takes its parent's
    # name ("HeartRateBpm/Value" is heart_rate_bpm).
    def field_name(parent, element)
      name = element.name == "Value" && parent.kind == :field ? parent.element.name : element.name
      Naming.snake_case(name).to_sym
    end

    # The schema key of an element, or nil for a namespace the schema does
    # not cover here.
    def segment(element)
      case element.namespace
      when NAMESPACE then element.name
      when ACTIVITY_EXTENSION_NAMESPACE then AX2_SEGMENTS[element.name] || "ax2:#{element.name}"
      end
    end

    def attribute_segment(attribute)
      case attribute.namespace
      when nil then "@#{attribute.name}"
      when XSI_NAMESPACE then "@xsi:#{attribute.name}"
      end
    end

    def document_message(element)
      frame = Frame.new(:document, element, {}, Schema::EMPTY)
      add_attributes(Node.new(:message, element, frame, "", ""))
      frame.to_message
    end
  end
end
