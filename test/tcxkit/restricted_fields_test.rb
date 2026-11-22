# frozen_string_literal: true

require_relative "../test_helper"

# Length, pattern and enumeration restrictions of the TCX v2 schema:
# RestrictedToken_t, CoursePointName_t, CoursePointType_t, LangID_t and
# PartNumber_t.
class RestrictedFieldsTest < Minitest::Test
  def course(name: "Loop", point_name: "Turn", point_type: "Left")
    Documents.messages(Documents.tcx(<<~XML))
      <Courses><Course>
        <Name>#{name}</Name>
        <CoursePoint>
          <Name>#{point_name}</Name><Time>2026-01-01T08:00:00Z</Time>
          <Position><LatitudeDegrees>1</LatitudeDegrees><LongitudeDegrees>2</LongitudeDegrees></Position>
          <PointType>#{point_type}</PointType>
        </CoursePoint>
      </Course></Courses>
    XML
  end

  def point(**options) = course(**options).find { |message| message.name == :course_point }
  def course_message(**options) = course(**options).find { |message| message.name == :course }

  def author(lang_id: "en", part_number: "006-A1234-00")
    Documents.message(Documents.tcx(<<~XML), :author)
      <Author xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Application_t">
        <Name>Exporter</Name>
        <Build><Version><VersionMajor>1</VersionMajor><VersionMinor>0</VersionMinor></Version></Build>
        <LangID>#{lang_id}</LangID><PartNumber>#{part_number}</PartNumber>
      </Author>
    XML
  end

  def plan_name(name)
    xml = Documents.tcx(%(<Activities><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
      <Training VirtualPartner="false"><Plan Type="Workout" IntervalWorkout="false"><Name>#{name}</Name></Plan></Training>
      </Activity></Activities>))
    Documents.message(xml, :activity).field("Training/Plan/Name")
  end

  def test_course_point_types
    {
      "Generic" => :generic, "Summit" => :summit, "First Aid" => :first_aid, " First   Aid " => :first_aid,
      "4th Category" => :"4th_category", "Hors Category" => :hors_category, "Sprint" => :sprint
    }.each do |text, value|
      assert_equal value, point(point_type: text)[:point_type], text
    end
    assert_equal :course_point_type, point.field(:point_type).type
  end

  def test_course_point_types_outside_the_enumeration
    ["left", "Turn", "5th Category", ""].each do |text|
      field = point(point_type: text).field(:point_type)
      assert_nil field.value, text
      assert_equal(text.empty? ? :empty : :not_in_enumeration, field.invalid_reason, text)
    end
  end

  def test_course_point_names_are_1_to_10_characters
    assert_equal "Turn left", point(point_name: " Turn  left ")[:name]
    assert_equal "Café crème", point(point_name: "Café crème")[:name]
    assert_equal :too_long, point(point_name: "Turn left now").field(:name).invalid_reason
    assert_equal :too_short, point(point_name: "  ").field(:name).invalid_reason
    assert_equal "Turn left now", point(point_name: "Turn left now").field(:name).raw_value
  end

  def test_course_and_plan_names_are_1_to_15_characters
    assert_equal "Fifteen chars!!", course_message(name: "Fifteen chars!!")[:name]
    assert_equal :too_long, course_message(name: "Sixteen chars!!!").field(:name).invalid_reason
    assert_equal :too_short, course_message(name: "").field(:name).invalid_reason
    assert_equal "Intervals", plan_name("Intervals").value
    assert_equal :restricted_token, plan_name("Intervals").type
    assert_equal :too_long, plan_name("Very long interval plan").invalid_reason
  end

  def test_lang_id_is_exactly_2_characters
    assert_equal "nl", author(lang_id: "nl")[:lang_id]
    assert_equal :too_long, author(lang_id: "nld").field(:lang_id).invalid_reason
    assert_equal :too_short, author(lang_id: "n").field(:lang_id).invalid_reason
  end

  def test_part_numbers_follow_the_pattern
    assert_equal "006-A1234-00", author[:part_number]
    assert_equal "ABC-12345-Z9", author(part_number: " ABC-12345-Z9 ")[:part_number]
    ["006-a1234-00", "006-A123-00", "006-A1234-000", "006A123400", "x006-A1234-00"].each do |text|
      assert_equal :no_pattern_match, author(part_number: text).field(:part_number).invalid_reason, text
    end
  end

  # XSD 1.1 allows "+" on unsigned types, and "-" before zero; XSD 1.0 does
  # not. The value is unambiguous, so the lenient rule is kept.
  def test_unsigned_integers_accept_the_xsd_1_1_signs
    assert_equal 7, Documents.message(Documents.trackpoint("<Cadence>+007</Cadence>"), :trackpoint)[:cadence]
    assert_equal 0, Documents.message(Documents.trackpoint("<Cadence>-0</Cadence>"), :trackpoint)[:cadence]
    assert_equal :not_an_integer,
                 Documents.message(Documents.trackpoint("<Cadence>-1</Cadence>"), :trackpoint).field(:cadence).invalid_reason
  end
end
