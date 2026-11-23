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

    # What a node in the element stack is: the root, a container, a message
    # element (with its Frame) or a field element (with its Shape).
    Node = Struct.new(:kind, :element, :frame, :shape)

    # Where an element or attribute sits inside a message: its path, schema
    # key (nil once a segment is outside the schema's namespaces), field name
    # and type. Every trackpoint has the same few shapes, so they are made
    # once per message type and reused; a builder makes at most SHAPE_LIMIT,
    # because unknown names come from the file.
    class Shape
      attr_reader :path, :key, :name, :spec, :local_name

      def initialize(path:, key:, name:, spec:, local_name:)
        @path = path
        @key = key
        @name = name
        @spec = spec
        @local_name = local_name
        @children = {}
        @attributes = {}
      end

      def child(namespace, name) = @children[namespace]&.[](name)
      def attribute(namespace, name) = @attributes[namespace]&.[](name)
      def add_child(namespace, name, shape) = (@children[namespace] ||= {})[name] = shape
      def add_attribute(namespace, name, shape) = (@attributes[namespace] ||= {})[name] = shape
    end

    SHAPE_LIMIT = 10_000

    # A message being collected.
    class Frame
      attr_reader :kind, :element, :context, :fields, :table, :shape

      def initialize(kind, element, context, table, shape)
        @kind = kind
        @element = element
        @context = context.freeze
        @table = table
        @shape = shape
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

    def initialize(&emit)
      @emit = emit
      @nodes = []
      @counters = Hash.new(0)
      @roots = {}.compare_by_identity
      @shapes = 0
    end

    def handle(type, element)
      type == :start ? start(element) : finish(element)
    end

    private

    def start(element)
      parent = @nodes.last
      return @nodes << Node.new(:root, element, nil, nil) unless parent

      kind = message_kind(element, parent)
      if kind
        @nodes << open_message(kind, element, parent.frame)
      elsif container?(element, parent)
        @nodes << Node.new(:container, element, parent.frame, nil)
      elsif parent.frame
        frame = parent.frame
        node = Node.new(:field, element, frame, child_shape(parent.shape || frame.shape, element, frame.table))
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
      frame = new_frame(kind, element, context, Schema.table(kind, context))
      node = Node.new(:message, element, frame, frame.shape)
      add_attributes(node)
      node
    end

    def new_frame(kind, element, context, table)
      root = @roots[table] ||= Shape.new(path: "", key: "", name: nil, spec: nil, local_name: nil)
      Frame.new(kind, element, context, table, root)
    end

    def next_document_index(kind)
      index = @counters[kind]
      @counters[kind] += 1
      index
    end

    # The shape of a child element: the parent's path and key joined with
    # this element; a Value element takes its parent's name
    # ("HeartRateBpm/Value" is heart_rate_bpm).
    def child_shape(parent, element, table)
      cached = parent.child(element.namespace, element.name)
      return cached if cached

      local = element.name
      key = join_key(parent.key, segment(element))
      named = local == "Value" && parent.local_name ? parent.local_name : local
      shape = Shape.new(path: join(parent.path, local), key: key, name: Naming.snake_case(named).to_sym,
                        spec: (key && table[key]) || Types::UNKNOWN, local_name: local)
      parent.add_child(element.namespace, local, shape) if remember?
      shape
    end

    def attribute_shape(parent, attribute, table)
      cached = parent.attribute(attribute.namespace, attribute.name)
      return cached if cached

      key = join_key(parent.key, attribute_segment(attribute))
      shape = Shape.new(path: join(parent.path, "@#{attribute.name}"), key: key,
                        name: Naming.snake_case(attribute.name).to_sym, spec: (key && table[key]) || Types::UNKNOWN,
                        local_name: nil)
      parent.add_attribute(attribute.namespace, attribute.name, shape) if remember?
      shape
    end

    def remember?
      (@shapes += 1) <= SHAPE_LIMIT
    end

    def join(path, segment)
      path.empty? ? segment.dup.freeze : "#{path}/#{segment}".freeze
    end

    def join_key(key, segment)
      key && segment && join(key, segment)
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
        shape = attribute_shape(node.shape, attribute, node.frame.table)
        node.frame.fields << Field.new(name: shape.name, path: shape.path, namespace: attribute.namespace,
                                       text: attribute.value, spec: shape.spec, line: node.element.line)
      end
    end

    # An empty Extensions is not a field, and neither is the missing text of
    # an element that only carries attributes (such as <TPX CadenceSensor="Bike"/>).
    def add_text(node, element)
      return if element.name == "Extensions" && element.text.strip.empty?
      return if element.text.empty? && !element.attributes.empty?

      shape = node.shape
      node.frame.fields << Field.new(name: shape.name, path: shape.path, namespace: element.namespace,
                                     text: element.text, spec: shape.spec, line: element.line)
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
      frame = new_frame(:document, element, {}, Schema::EMPTY)
      add_attributes(Node.new(:message, element, frame, frame.shape))
      frame.to_message
    end
  end
end
