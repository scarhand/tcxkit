# frozen_string_literal: true

require_relative "../../test_helper"

class ParserTest < Minitest::Test
  def test_streams_start_and_end_events_with_text
    rows = Documents.events("<a><b>1.5</b><c x='y'/></a>")

    assert_equal [
      [:start, "a", 1, nil], [:start, "b", 2, nil], [:end, "b", 2, "1.5"],
      [:start, "c", 2, nil], [:end, "c", 2, ""], [:end, "a", 1, nil]
    ], rows
  end

  def test_elements_carry_namespace_attributes_and_position
    elements = []
    xml = %(<r xmlns="urn:a" xmlns:b="urn:b">\n  <b:p b:q="1" s="2">t</b:p>\n</r>)
    TcxKit::XML::Parser.new(StringIO.new(xml), limits: TcxKit::Limits::DEFAULT, source_label: "t")
                       .each_event { |type, element| elements << element if type == :end }
    p = elements.first

    assert_equal ["urn:b", "p", 2], [p.namespace, p.name, p.line]
    assert_equal "1", p.attribute("q", namespace: "urn:b").value
    assert_equal "2", p.attribute("s").value
    assert_predicate p, :frozen?
  end

  def test_text_of_a_parent_is_dropped_once_it_has_children
    rows = Documents.events("<a>stray <b>x</b> text</a>")

    assert_nil rows.last[3]
  end

  def test_predefined_entities_character_references_and_cdata_are_text
    rows = Documents.events("<a>&lt;&amp;&#65;&#x42;<![CDATA[<c>]]></a>")

    assert_equal "<&AB<c>", rows.last[3]
  end

  def test_keeps_text_exactly_as_written
    rows = Documents.events("<a>  12.50\n </a>")

    assert_equal "  12.50\n ", rows.last[3]
  end

  def test_multibyte_text
    rows = Documents.events("<a>Zoë – 5 km</a>")

    assert_equal "Zoë – 5 km", rows.last[3]
    assert_equal Encoding::UTF_8, rows.last[3].encoding
  end

  def test_errors_from_the_callers_block_propagate
    parser = TcxKit::XML::Parser.new(StringIO.new("<a><b/></a>"), limits: TcxKit::Limits::DEFAULT, source_label: "t")

    assert_raises(KeyError) { parser.each_event { |_type, _element| raise KeyError } }
  end

  def test_reads_once
    parser = TcxKit::XML::Parser.new(StringIO.new("<a/>"), limits: TcxKit::Limits::DEFAULT, source_label: "t")
    parser.each_event { |*| nil }

    assert_raises(TcxKit::Error) { parser.each_event { |*| nil } }
  end
end
