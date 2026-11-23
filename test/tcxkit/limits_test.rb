# frozen_string_literal: true

require_relative "../test_helper"

class LimitsTest < Minitest::Test
  def test_defaults
    assert_equal({ max_bytes: 64 * 1024 * 1024, max_elements: 5_000_000, max_depth: 64,
                   max_text_bytes: 1024 * 1024, max_seconds: nil }, TcxKit::Limits::DEFAULT.to_h)
  end

  def test_none_switches_every_limit_off
    assert TcxKit::Limits.none.to_h.values.all?(&:nil?)
  end

  def test_rejects_non_positive_values
    assert_raises(ArgumentError) { TcxKit::Limits.new(max_depth: 0) }
    assert_raises(ArgumentError) { TcxKit::Limits.new(max_bytes: "1") }
  end

  def test_a_hash_keeps_the_other_defaults
    limits = TcxKit::Limits.coerce(max_depth: 5)

    assert_equal 5, limits.max_depth
    assert_equal 5_000_000, limits.max_elements
  end

  def test_max_bytes
    xml = Documents.tcx("<Notes>#{'x' * 200_000}</Notes>")

    assert_limit(:max_bytes) { Documents.read(xml, limits: { max_bytes: 100_000 }) }
    assert_nil Documents.read(xml, limits: { max_bytes: xml.bytesize })
  end

  def test_max_bytes_counts_the_prolog
    xml = "<!-- #{'x' * 5000} -->#{Documents.tcx(declaration: false)}"

    assert_limit(:max_bytes) { Documents.read(xml, limits: { max_bytes: 1000 }) }
  end

  def test_max_elements
    xml = Documents.tcx("<a/>" * 10)

    assert_limit(:max_elements) { Documents.read(xml, limits: { max_elements: 10 }) }
    assert_nil Documents.read(xml, limits: { max_elements: 11 })
  end

  def test_max_depth
    xml = Documents.tcx(("<a>" * 10) + ("</a>" * 10))

    error = assert_limit(:max_depth) { Documents.read(xml, limits: { max_depth: 10 }) }
    assert_equal 3, error.line
    assert_nil Documents.read(xml, limits: { max_depth: 11 })
  end

  def test_max_text_bytes_for_text_attributes_and_the_prolog
    assert_limit(:max_text_bytes) { Documents.read(Documents.tcx("<a>#{'x' * 101}</a>"), limits: { max_text_bytes: 100 }) }
    assert_limit(:max_text_bytes) { Documents.read(Documents.tcx("<a b='#{'x' * 101}'/>"), limits: { max_text_bytes: 100 }) }
    assert_limit(:max_text_bytes) do
      Documents.read("<!-- #{'x' * 200} -->#{Documents.tcx(declaration: false)}", limits: { max_text_bytes: 100 })
    end
    assert_nil Documents.read(Documents.tcx("<a>#{'x' * 100}</a>"), limits: { max_text_bytes: 100 })
  end

  def test_text_between_child_elements_does_not_count
    xml = Documents.tcx("<a>#{"<b/>#{' ' * 60}" * 10}</a>")

    assert_nil Documents.read(xml, limits: { max_text_bytes: 100 })
  end

  def test_max_seconds_excludes_the_callers_block
    xml = Documents.tcx("<Folders/><Workouts/><Extensions/>")
    names = []
    TcxKit::Reader.new(StringIO.new(xml), limits: { max_seconds: 0.05 }).each_message do |message|
      sleep 0.03
      names << message.name
    end

    assert_equal %i[element element element document], names
  end

  def test_max_seconds_counts_the_message_builder
    # The clock is checked every 64 elements; time spent handling events
    # inside the gem (here, a slow event block) counts.
    xml = Documents.tcx("<a/>" * 200)
    parser = TcxKit::XML::Parser.new(StringIO.new(xml), limits: TcxKit::Limits.new(max_seconds: 0.05), source_label: "t")

    assert_raises(TcxKit::LimitExceededError) do
      parser.each_event { |*| sleep 0.001 }
    end
  end

  def test_max_seconds
    xml = Documents.tcx("<a>x</a>" * 200_000)

    assert_limit(:max_seconds) { Documents.read(xml, limits: { max_seconds: 0.001 }) }
  end

  def test_max_seconds_counts_an_input_that_trickles_in
    slow = Class.new(Documents::ShortReads) do
      def read(*)
        sleep 0.001
        super
      end
    end
    xml = Documents.tcx("<a/>" * 1000)

    assert_limit(:max_seconds) { TcxKit::Reader.new(slow.new(xml, 1), limits: { max_seconds: 0.05 }).each_message { |*| nil } }
  end

  private

  def assert_limit(limit, &block)
    error = assert_raises(TcxKit::LimitExceededError, &block)
    assert_equal limit, error.limit
    error
  end
end
