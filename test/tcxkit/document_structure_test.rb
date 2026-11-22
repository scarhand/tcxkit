# frozen_string_literal: true

require_relative "../test_helper"

class DocumentStructureTest < Minitest::Test
  LAP = <<~XML
    <TotalTimeSeconds>60</TotalTimeSeconds><DistanceMeters>100</DistanceMeters><Calories>5</Calories>
    <Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
  XML

  def summary(xml)
    Documents.messages(xml).map { |message| [message.name, message.context] }
  end

  def test_several_activities_are_counted_across_the_document
    xml = Documents.tcx(<<~XML)
      <Activities>
        <Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id><Lap StartTime="2026-01-01T08:00:00Z">#{LAP}</Lap></Activity>
        <Activity Sport="Biking"><Id>2026-01-02T08:00:00Z</Id><Lap StartTime="2026-01-02T08:00:00Z">#{LAP}</Lap></Activity>
      </Activities>
    XML

    assert_equal [[:lap, { activity: 0, lap: 0 }], [:activity, { activity: 0 }],
                  [:lap, { activity: 1, lap: 0 }], [:activity, { activity: 1 }], [:document, {}]], summary(xml)
  end

  def test_multisport_sessions
    xml = Documents.tcx(<<~XML)
      <Activities>
        <MultiSportSession>
          <Id>2026-01-01T08:00:00Z</Id>
          <FirstSport><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id><Lap StartTime="2026-01-01T08:00:00Z">#{LAP}</Lap></Activity></FirstSport>
          <NextSport>
            <Transition StartTime="2026-01-01T08:01:00Z">#{LAP}</Transition>
            <Activity Sport="Biking"><Id>2026-01-01T08:02:00Z</Id><Lap StartTime="2026-01-01T08:02:00Z">#{LAP}</Lap></Activity>
          </NextSport>
          <Notes>brick</Notes>
        </MultiSportSession>
      </Activities>
    XML
    messages = Documents.messages(xml)

    assert_equal [[:lap, { multi_sport_session: 0, activity: 0, lap: 0 }],
                  [:activity, { multi_sport_session: 0, activity: 0 }],
                  [:transition, { multi_sport_session: 0, transition: 0 }],
                  [:lap, { multi_sport_session: 0, activity: 1, lap: 0 }],
                  [:activity, { multi_sport_session: 0, activity: 1 }],
                  [:multi_sport_session, { multi_sport_session: 0 }], [:document, {}]], summary(xml)
    session = messages.find { |message| message.name == :multi_sport_session }
    assert_equal [Time.utc(2026, 1, 1, 8), "brick"], session.to_h.values_at(:id, :notes)
    assert_equal Time.utc(2026, 1, 1, 8, 1), messages.find { |message| message.name == :transition }[:start_time]
    assert_equal :biking, messages.select { |message| message.name == :activity }.last[:sport]
  end

  def test_courses
    xml = Documents.tcx(<<~XML)
      <Courses>
        <Course>
          <Name>Loop</Name>
          <Lap>
            <TotalTimeSeconds>600</TotalTimeSeconds><DistanceMeters>2000</DistanceMeters>
            <BeginPosition><LatitudeDegrees>1.5</LatitudeDegrees><LongitudeDegrees>2.5</LongitudeDegrees></BeginPosition>
            <EndPosition><LatitudeDegrees>1.6</LatitudeDegrees><LongitudeDegrees>2.6</LongitudeDegrees></EndPosition>
            <Intensity>Active</Intensity>
          </Lap>
          <Track><Trackpoint><Time>2026-01-01T08:00:00Z</Time></Trackpoint></Track>
          <CoursePoint>
            <Name>Turn</Name><Time>2026-01-01T08:05:00Z</Time>
            <Position><LatitudeDegrees>1.55</LatitudeDegrees><LongitudeDegrees>2.55</LongitudeDegrees></Position>
            <PointType>Left</PointType>
          </CoursePoint>
        </Course>
      </Courses>
    XML
    messages = Documents.messages(xml)

    assert_equal [[:lap, { course: 0, lap: 0 }], [:trackpoint, { course: 0, track: 0, trackpoint: 0 }],
                  [:track, { course: 0, track: 0 }], [:course_point, { course: 0, course_point: 0 }],
                  [:course, { course: 0 }], [:document, {}]], summary(xml)
    lap = messages.first
    assert_equal [1.5, 1.6], [lap["BeginPosition/LatitudeDegrees"], lap["EndPosition/LatitudeDegrees"]]
    assert lap.fields.all?(&:known?)
    assert_equal ["Turn", :left, 1.55], messages[3].to_h.values_at(:name, :point_type, :latitude_degrees)
    assert_equal "Loop", messages[4][:name]
  end

  def test_other_top_level_elements_are_generic_messages
    xml = Documents.tcx(<<~XML)
      <Folders><History><Running Name="Runs"><Notes>n</Notes></Running></History></Folders>
      <Workouts><Workout Sport="Running"><Name>Easy</Name></Workout></Workouts>
      <Extensions><Thing xmlns="urn:x">1</Thing></Extensions>
    XML
    messages = Documents.messages(xml)

    assert_equal [[:element, "Folders"], [:element, "Workouts"], [:element, "Extensions"], [:document, "TrainingCenterDatabase"]],
                 messages.map { |message| [message.name, message.element_name] }
    assert_equal [{ element: 0 }, { element: 1 }, { element: 2 }], messages.first(3).map(&:context)
    assert_equal ["History/Running/@Name", "History/Running/Notes"], messages[0].fields.map(&:path)
    assert_equal "Easy", messages[1]["Workout/Name"]
    refute messages.first(3).flat_map(&:fields).any?(&:known?)
  end

  def test_message_elements_only_count_where_the_schema_puts_them
    xml = Documents.tcx(<<~XML)
      <Activities>
        <Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
          <Lap StartTime="2026-01-01T08:00:00Z">#{LAP}<Trackpoint><Time>2026-01-01T08:00:00Z</Time></Trackpoint></Lap>
          <Extensions><Lap xmlns="#{TcxKit::NAMESPACE}"><Calories>1</Calories></Lap></Extensions>
        </Activity>
      </Activities>
    XML
    messages = Documents.messages(xml)

    assert_equal %i[lap activity document], messages.map(&:name)
    assert_equal "2026-01-01T08:00:00Z", messages[0]["Trackpoint/Time"]
    assert_equal "1", messages[1]["Extensions/Lap/Calories"]
  end

  def test_fields_are_not_kept_after_their_message
    xml = Documents.tcx("<Activities><Activity Sport=\"Other\"><Id>2026-01-01T08:00:00Z</Id></Activity></Activities>")
    first = Documents.messages(xml).first

    assert_equal %i[sport id], first.fields.map(&:name)
  end
end
