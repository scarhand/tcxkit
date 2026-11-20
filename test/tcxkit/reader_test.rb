# frozen_string_literal: true

require_relative "../test_helper"
require "tempfile"

class ReaderTest < Minitest::Test
  def test_reads_a_tcx_v2_document
    assert_nil Documents.read(Documents.tcx)
  end

  def test_external_iteration
    enumerator = TcxKit::Reader.new(Documents.fixture("activity.tcx")).each_message

    assert_equal :trackpoint, enumerator.next.name
    assert_equal :trackpoint, enumerator.next.name
    assert_equal :track, enumerator.next.name
  end

  def test_each_message_without_a_block_returns_an_enumerator
    enumerator = TcxKit::Reader.new(StringIO.new(Documents.tcx)).each_message

    assert_kind_of Enumerator, enumerator
    assert_equal [:document], enumerator.map(&:name)
  end

  def test_skips_whitespace_before_the_xml_declaration
    assert_nil Documents.read("   \r\n\t#{Documents.tcx}")
    assert_nil Documents.read("\xEF\xBB\xBF  #{Documents.tcx}")
  end

  def test_rejects_another_root_element
    error = assert_raises(TcxKit::UnsupportedFormatError) do
      Documents.read(%(<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1"/>))
    end

    assert_match(/root element is gpx/, error.message)
    assert_equal 1, error.line
  end

  def test_rejects_tcx_v1
    error = assert_raises(TcxKit::UnsupportedFormatError) do
      Documents.read(%(<TrainingCenterDatabase xmlns="#{TcxKit::NAMESPACE_V1}"/>))
    end

    assert_match(/TCX v1/, error.message)
  end

  def test_rejects_a_root_outside_the_namespace
    assert_raises(TcxKit::UnsupportedFormatError) { Documents.read("<TrainingCenterDatabase/>") }
  end

  def test_reads_paths_and_pathnames
    Tempfile.create(["activity", ".tcx"]) do |file|
      file.write(Documents.tcx)
      file.close

      assert_nil TcxKit::Reader.new(file.path).each_message { |*| nil }
      assert_nil TcxKit::Reader.new(Pathname.new(file.path)).each_message { |*| nil }
      assert_equal file.path, TcxKit::Reader.new(file.path).source_label
    end
  end

  def test_a_seekable_io_can_be_read_again_from_its_starting_position
    io = StringIO.new("junk#{Documents.tcx}")
    io.read(4)
    reader = TcxKit::Reader.new(io)

    2.times { assert_nil reader.each_message { |*| nil } }
    refute_predicate io, :closed?
  end

  def test_a_non_seekable_io_can_be_read_once
    reader, writer = IO.pipe
    writer.write(Documents.tcx)
    writer.close
    tcx = TcxKit::Reader.new(reader)
    tcx.each_message { |*| nil }

    assert_raises(TcxKit::Error) { tcx.each_message { |*| nil } }
  ensure
    reader&.close
  end

  def test_close_io_closes_the_callers_io
    io = StringIO.new(Documents.tcx)
    reader = TcxKit::Reader.new(io, close_io: true)
    reader.each_message { |*| nil }

    assert_predicate io, :closed?
    assert_raises(TcxKit::Error) { reader.each_message { |*| nil } }
  end

  def test_close_io_closes_even_after_an_error
    io = StringIO.new("<oops")

    assert_raises(TcxKit::Error) { TcxKit::Reader.new(io, close_io: true).each_message { |*| nil } }
    assert_predicate io, :closed?
  end

  def test_source_label
    error = assert_raises(TcxKit::InvalidFileError) { Documents.read(Documents.tcx("<a></b>"), source_label: "upload 7") }

    assert_equal "upload 7", error.source
  end

  def test_rejects_other_sources
    assert_raises(ArgumentError) { TcxKit::Reader.new(42) }
    assert_raises(ArgumentError) { TcxKit::Reader.new(StringIO.new(""), limits: :none) }
  end
end
