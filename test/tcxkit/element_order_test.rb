# frozen_string_literal: true

require_relative "../test_helper"

# Section 7: elements in an order the schema does not allow are read
# through, each typed where it is.
class ElementOrderTest < Minitest::Test
  def test_trackpoint_children_in_any_order
    xml = Documents.trackpoint(<<~XML)
      <Extensions><TPX xmlns="#{TcxKit::ACTIVITY_EXTENSION_NAMESPACE}"><Watts>200</Watts><Speed>3.0</Speed></TPX></Extensions>
      <HeartRateBpm><Value>130</Value></HeartRateBpm>
      <Position><LongitudeDegrees>2.5</LongitudeDegrees><LatitudeDegrees>1.5</LatitudeDegrees></Position>
      <Time>2026-01-01T08:00:00Z</Time>
    XML
    point = Documents.message(xml, :trackpoint)

    assert_equal [200, 3.0, 130, 2.5, 1.5, Time.utc(2026, 1, 1, 8)],
                 point.to_h.values_at(:watts, :speed, :heart_rate_bpm, :longitude_degrees, :latitude_degrees, :time)
    assert point.fields.all?(&:known?)
  end

  def test_lap_fields_after_its_track_and_an_activity_id_after_its_laps
    xml = Documents.tcx(<<~XML)
      <Activities><Activity Sport="Biking">
        <Lap StartTime="2026-01-01T08:00:00Z">
          <Track><Trackpoint><Time>2026-01-01T08:00:00Z</Time></Trackpoint></Track>
          <TriggerMethod>Time</TriggerMethod><DistanceMeters>100</DistanceMeters><TotalTimeSeconds>60</TotalTimeSeconds>
        </Lap>
        <Creator><ProductID>3</ProductID><Name>Watch</Name></Creator>
        <Id>2026-01-01T08:00:00Z</Id>
      </Activity></Activities>
    XML
    messages = Documents.messages(xml)
    lap = messages.find { |message| message.name == :lap }

    assert_equal %i[trackpoint track lap creator activity document], messages.map(&:name)
    assert_equal [:time, 100.0, 60.0], lap.to_h.values_at(:trigger_method, :distance_meters, :total_time_seconds)
    assert_equal [3, "Watch"], messages[3].to_h.values_at(:product_id, :name)
    assert_equal Time.utc(2026, 1, 1, 8), messages[4][:id]
  end

  def test_a_lap_without_required_elements_has_those_fields_absent
    xml = Documents.tcx(%(<Activities><Activity Sport="Other"><Id>2026-01-01T08:00:00Z</Id>
      <Lap StartTime="2026-01-01T08:00:00Z"><Calories>5</Calories></Lap></Activity></Activities>))
    lap = Documents.message(xml, :lap)

    assert_equal %i[start_time calories], lap.fields.map(&:name)
    assert_nil lap[:total_time_seconds]
  end
end
