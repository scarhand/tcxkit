# frozen_string_literal: true

module TcxKit
  module XML
    # An attribute as written: namespace URI (nil for none), local name and value.
    Attribute = Struct.new(:namespace, :name, :value, keyword_init: true)

    # One XML element. Its text is known when it closes: the text as written
    # for an element without child elements, nil for one with children.
    class Element
      attr_reader :namespace, :name, :attributes, :line, :column, :depth, :text

      def initialize(namespace:, name:, attributes:, line:, column:, depth:)
        @namespace = namespace
        @name = name
        @attributes = attributes
        @line = line
        @column = column
        @depth = depth
        @children = false
        @buffer = nil
        @text = nil
      end

      def children?
        @children
      end

      def attribute(name, namespace: nil)
        attributes.find { |attribute| attribute.name == name && attribute.namespace == namespace }
      end

      # Called by the Parser while reading.

      def child_started!
        @children = true
        @buffer = nil
      end

      # Appends text and returns the text's size in bytes so far.
      def append_text(string)
        return 0 if @children

        (@buffer ||= +"") << string
        @buffer.bytesize
      end

      def finish!
        @text = @children ? nil : (@buffer || "").freeze
        @buffer = nil
        freeze
      end
    end
  end
end
