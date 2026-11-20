# frozen_string_literal: true

require_relative "../test_helper"

class FieldsTest < Minitest::Test
  def point(children)
    Documents.message(Documents.trackpoint(children), :trackpoint)
  end

  def field(children, name)
    point(children).field(name)
  end

  def test_doubles
    assert_in_delta 1000.0, field("<AltitudeMeters> 1e3\n</AltitudeMeters>", :altitude_meters).value
    assert_in_delta(-0.5, field("<AltitudeMeters>-.5</AltitudeMeters>", :altitude_meters).value)
    assert_equal " 1e3\n", field("<AltitudeMeters> 1e3\n</AltitudeMeters>", :altitude_meters).text
    assert_equal "1e3", field("<AltitudeMeters> 1e3\n</AltitudeMeters>", :altitude_meters).raw_value
    assert_equal :not_a_number, field("<AltitudeMeters>12,5</AltitudeMeters>", :altitude_meters).invalid_reason
    assert_equal :not_finite, field("<AltitudeMeters>INF</AltitudeMeters>", :altitude_meters).invalid_reason
    assert_equal :not_finite, field("<AltitudeMeters>NaN</AltitudeMeters>", :altitude_meters).invalid_reason
    assert_equal :empty, field("<AltitudeMeters> </AltitudeMeters>", :altitude_meters).invalid_reason
  end

  def test_position_ranges
    position = ->(lat, lon) { point("<Position><LatitudeDegrees>#{lat}</LatitudeDegrees><LongitudeDegrees>#{lon}</LongitudeDegrees></Position>") }

    assert_equal [90.0, -180.0], position.call("90", "-180").to_h.values_at(:latitude_degrees, :longitude_degrees)
    assert_equal :out_of_range, position.call("90.1", "0").field(:latitude_degrees).invalid_reason
    assert_equal :out_of_range, position.call("0", "180").field(:longitude_degrees).invalid_reason
    assert_equal :out_of_range, position.call("0", "-180.1").field(:longitude_degrees).invalid_reason
  end

  def test_integers
    assert_equal 255, field("<HeartRateBpm><Value>255</Value></HeartRateBpm>", :heart_rate_bpm).value
    assert_equal :out_of_range, field("<HeartRateBpm><Value>256</Value></HeartRateBpm>", :heart_rate_bpm).invalid_reason
    assert_equal :not_an_integer, field("<HeartRateBpm><Value>142.0</Value></HeartRateBpm>", :heart_rate_bpm).invalid_reason
    assert_equal :not_an_integer, field("<HeartRateBpm><Value>-5</Value></HeartRateBpm>", :heart_rate_bpm).invalid_reason
    assert_equal 254, field("<Cadence>254</Cadence>", :cadence).value
    assert_equal :out_of_range, field("<Cadence>255</Cadence>", :cadence).invalid_reason
    assert_equal 7, field("<Cadence>+007</Cadence>", :cadence).value
  end

  def test_date_times
    assert_equal Time.utc(2026, 1, 1, 7, 30), field("<Time>2026-01-01T08:30:00+01:00</Time>", :time).value
    assert_equal Time.utc(2026, 1, 1, 8, 0, Rational(123, 1000)), field("<Time>2026-01-01T08:00:00.123Z</Time>", :time).value
    assert_predicate field("<Time>2026-01-01T08:00:00Z</Time>", :time).value, :utc?
    assert_equal Time.utc(2024, 2, 29), field("<Time>2024-02-29T00:00:00Z</Time>", :time).value

    {
      "2026-01-01T08:00:00" => :no_utc_offset,
      "2026-01-01 08:00:00Z" => :not_a_date_time,
      "2026-02-29T00:00:00Z" => :not_a_date_time,
      "2026-13-01T00:00:00Z" => :not_a_date_time,
      "2026-01-01T24:00:00Z" => :not_a_date_time,
      "2026-01-01T08:00:60Z" => :not_a_date_time,
      "2026-01-01T08:00:00+15:00" => :not_a_date_time,
      "1767254400" => :not_a_date_time
    }.each do |text, reason|
      time = field("<Time>#{text}</Time>", :time)
      assert_equal reason, time.invalid_reason, text
      assert_nil time.value
      assert_equal text, time.raw_value
    end
  end

  def test_enumerations
    assert_equal :absent, field("<SensorState> Absent </SensorState>", :sensor_state).value
    assert_equal :not_in_enumeration, field("<SensorState>absent</SensorState>", :sensor_state).invalid_reason
    assert_equal :sensor_state, field("<SensorState>Absent</SensorState>", :sensor_state).type
  end

  def test_extension_elements_count_only_in_their_namespace
    other = field(%(<Extensions><TPX xmlns="urn:other"><Speed>3.0</Speed></TPX></Extensions>), :speed)
    tcx = field(%(<Extensions><TPX><Speed>3.0</Speed></TPX></Extensions>), :speed)

    refute_predicate other, :known?
    assert_equal "3.0", other.value
    refute_predicate tcx, :known?
  end

  def test_extension_prefixes_do_not_matter
    xml = %(<Extensions><ax:TPX xmlns:ax="#{TcxKit::ACTIVITY_EXTENSION_NAMESPACE}"><ax:Watts>99</ax:Watts></ax:TPX></Extensions>)

    assert_equal 99, field(xml, :watts).value
  end

  def test_unknown_elements_in_the_tcx_namespace_are_kept
    unknown = field("<Pace>5:00</Pace>", :pace)

    refute_predicate unknown, :known?
    assert_equal "5:00", unknown.value
  end

  def test_repeated_elements_are_all_kept
    pt = point("<HeartRateBpm><Value>120</Value></HeartRateBpm><HeartRateBpm><Value>121</Value></HeartRateBpm>")

    assert_equal [120, 121], pt.fields_named(:heart_rate_bpm).map(&:value)
    assert_equal 120, pt[:heart_rate_bpm]
  end

  def test_an_element_with_only_attributes_gives_only_its_attribute_fields
    xml = %(<Extensions><TPX xmlns="#{TcxKit::ACTIVITY_EXTENSION_NAMESPACE}" CadenceSensor="Bike"/></Extensions>)

    assert_equal [:cadence_sensor], point(xml).fields.map(&:name)
    assert_equal :bike, point(xml)[:cadence_sensor]
  end

  def test_empty_extensions_are_not_fields
    assert_equal [:time], point("<Time>2026-01-01T08:00:00Z</Time><Extensions/>").fields.map(&:name)
  end

  def test_whitespace_only_trackpoint_children_do_not_become_text_fields
    assert_equal [:time], point("\n  <Time>2026-01-01T08:00:00Z</Time>\n  ").fields.map(&:name)
  end
end
