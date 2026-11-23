# frozen_string_literal: true

require_relative "../test_helper"

# Quirks seen in files from real exporters, reproduced synthetically.
class ExporterQuirksTest < Minitest::Test
  ACTIVITY = <<~XML
    <Activities><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
      <Lap StartTime="2026-01-01T08:00:00Z"><TotalTimeSeconds>60</TotalTimeSeconds><DistanceMeters>200</DistanceMeters>
        <Calories>5</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
        <Track><Trackpoint><Time>2026-01-01T08:00:00Z</Time>%<point>s</Trackpoint></Track>
      </Lap><Notes>%<notes>s</Notes></Activity></Activities>
  XML

  def tcx(point: "", notes: "Café run", declaration: %(<?xml version="1.0" encoding="UTF-8"?>))
    %(#{declaration}\n<TrainingCenterDatabase xmlns="#{TcxKit::NAMESPACE}">\n#{format(ACTIVITY, point: point, notes: notes)}</TrainingCenterDatabase>\n)
  end

  def read(bytes)
    TcxKit::Activity.from_io(StringIO.new(bytes))
  end

  def test_an_undeclared_extension_prefix_is_read_without_a_namespace
    activity = read(tcx(point: "<Extensions><ns3:TPX><ns3:Speed>3.1</ns3:Speed></ns3:TPX></Extensions>"))
    field = activity.records.first.raw_message.field("Extensions/TPX/Speed")

    assert_equal ["3.1", nil], [field.value, field.namespace]
    refute_predicate field, :known?
    assert_nil activity.records.first.speed
    assert_equal :running, activity.sport
  end

  def test_an_empty_prefix_binding_is_read_without_a_namespace
    xml = tcx.sub("<TrainingCenterDatabase ", %(<TrainingCenterDatabase xmlns:p="" )).sub("<Notes>", "<p:Mood>good</p:Mood><Notes>")

    assert_equal "good", read(xml).session.raw_message["Mood"]
  end

  def test_other_errors_after_a_namespace_error_are_still_invalid
    xml = tcx(point: "<Extensions><ns3:TPX><ns3:Speed>3.1</ns3:Speed></ns3:TPX><a c='1' c='2'/></Extensions>")

    error = assert_raises(TcxKit::InvalidFileError) { read(xml) }
    assert_match(/redefined/, error.message)
  end

  def test_utf_16_documents
    declaration = %(<?xml version="1.0" encoding="UTF-16"?>)
    {
      "little-endian with a byte order mark" => "\xFF\xFE".b + tcx(declaration: declaration).encode("UTF-16LE").b,
      "big-endian with a byte order mark" => "\xFE\xFF".b + tcx(declaration: declaration).encode("UTF-16BE").b,
      "little-endian without one" => tcx(declaration: declaration).encode("UTF-16LE").b
    }.each do |label, bytes|
      activity = read(bytes)
      assert_equal ["Café run", 200.0], [activity.session.notes, activity.total_distance], label
    end
  end

  def test_a_dtd_in_a_utf_16_document_is_refused
    xml = %(<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE x [<!ENTITY e "y">]>) + tcx(declaration: "", notes: "&e;")

    assert_raises(TcxKit::UnsafeContentError) { read("\xFF\xFE".b + xml.encode("UTF-16LE").b) }
  end

  def test_single_byte_encodings_declared_in_the_xml_declaration
    latin1 = tcx(declaration: %(<?xml version="1.0" encoding="ISO-8859-1"?>)).encode("ISO-8859-1").b
    windows = tcx(declaration: %(<?xml version="1.0" encoding="windows-1252"?>), notes: "€5 run").encode("Windows-1252").b

    assert_equal "Café run", read(latin1).session.notes
    assert_equal "€5 run", read(windows).session.notes
  end

  def test_latin_1_bytes_in_a_utf_8_document_are_invalid
    bytes = tcx.b.sub("Caf\xC3\xA9".b, "Caf\xE9".b)

    error = assert_raises(TcxKit::InvalidFileError) { read(bytes) }
    assert_match(/encoding/i, error.message)
  end

  def test_crlf_line_endings
    activity = read(tcx(notes: "line one\nline two").gsub("\n", "\r\n"))

    assert_equal "line one\nline two", activity.session.notes
    assert_equal 200.0, activity.total_distance
  end

  def test_whitespace_and_a_byte_order_mark_before_the_declaration
    assert_equal :running, read("\xEF\xBB\xBF \r\n#{tcx}").sport
  end

  def test_near_miss_times_are_invalid_not_guessed
    {
      "2026-01-01T08:00:00+0000" => :not_a_date_time,
      "2026-01-01T08:00:00z" => :not_a_date_time,
      "2026-01-01 08:00:00Z" => :not_a_date_time,
      "2026-01-01T08:00:00" => :no_utc_offset
    }.each do |text, reason|
      lap = read(tcx.sub(%(StartTime="2026-01-01T08:00:00Z"), %(StartTime="#{text}"))).laps.first
      assert_nil lap.start_time, text
      assert_equal reason, lap.raw_message.field(:start_time).invalid_reason, text
    end
  end

  def test_a_decimal_heart_rate_is_invalid_with_its_text_kept
    record = read(tcx(point: "<HeartRateBpm><Value>142.0</Value></HeartRateBpm>")).records.first

    assert_nil record.heart_rate
    assert_equal ["142.0", :not_an_integer], record.raw_message.field(:heart_rate_bpm).then { |f| [f.raw_value, f.invalid_reason] }
  end
end
