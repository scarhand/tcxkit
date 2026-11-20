# frozen_string_literal: true

require_relative "../../test_helper"

class PrologTest < Minitest::Test
  def scan(text, complete: true)
    TcxKit::XML::Prolog.scan(text.b, complete: complete)
  end

  def test_done_at_the_root_element
    prolog = %(<?xml version="1.0"?>\n<!-- hi -->\n<?pi x?>)

    assert_equal prolog.bytesize, scan("#{prolog}<root>")
    assert_equal 3, scan("\xEF\xBB\xBF<root/>")
  end

  def test_a_doctype_without_internal_subset_is_allowed
    assert_equal 30, scan(%(<!DOCTYPE root SYSTEM "x.dtd"><root/>))
  end

  def test_an_internal_subset_is_unsafe
    assert_equal :unsafe, scan(%(<!DOCTYPE root [<!ENTITY e "x">]><root/>))
    assert_equal :unsafe, scan(%(<?xml version="1.0"?><!--c--><!DOCTYPE root SYSTEM 'a>b' [ ]><root/>))
  end

  def test_brackets_in_quotes_and_comments_are_not_a_subset
    assert_kind_of Integer, scan(%(<!DOCTYPE root SYSTEM "a[b"><root/>))
    assert_kind_of Integer, scan(%(<!-- <!DOCTYPE x [ --><root/>))
  end

  def test_asks_for_more_input_when_undecided
    ["", "  ", "<", "<!", "<!DOC", "<?xml version", "<!-- open", "<!DOCTYPE r SYSTEM \"x"].each do |text|
      assert_equal :more, scan(text, complete: false), text.inspect
      assert_kind_of Integer, scan(text, complete: true), text.inspect
    end
  end

  def test_non_xml_input_is_left_to_the_parser
    assert_equal 0, scan("\x0E\x10binary", complete: false)
  end
end
