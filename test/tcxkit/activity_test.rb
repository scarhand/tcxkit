# frozen_string_literal: true

require_relative "../test_helper"

class ActivityTest < Minitest::Test
  def activity
    @activity ||= TcxKit::Activity.read(Documents.fixture("activity.tcx"))
  end

  def read(xml)
    TcxKit::Activity.from_io(StringIO.new(xml))
  end

  LAP_FIELDS = <<~XML
    <TotalTimeSeconds>%<time>s</TotalTimeSeconds><DistanceMeters>%<distance>s</DistanceMeters>
    %<extra>s<Calories>%<calories>s</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
  XML

  def lap(start, time: 60, distance: 100, calories: 5, extra: "", points: "")
    track = points.empty? ? "" : "<Track>#{points}</Track>"
    %(<Lap StartTime="#{start}">#{format(LAP_FIELDS, time: time, distance: distance, calories: calories, extra: extra)}#{track}</Lap>)
  end

  def point(time, heart_rate = 120)
    "<Trackpoint><Time>#{time}</Time><HeartRateBpm><Value>#{heart_rate}</Value></HeartRateBpm></Trackpoint>"
  end

  def test_reads_paths_io_and_options
    assert_equal 2, TcxKit::Activity.from_file(Documents.fixture("activity.tcx")).laps.size
    assert_raises(TcxKit::LimitExceededError) do
      TcxKit::Activity.read(Documents.fixture("activity.tcx"), limits: { max_elements: 10 })
    end
  end

  def test_sessions_laps_and_records
    assert_equal 1, activity.sessions.size
    assert_equal 2, activity.laps.size
    assert_equal 3, activity.records.size
    assert_equal [2, 1], activity.laps.map { |lap| lap.records.size }
    assert_equal activity.laps, activity.session.laps
    assert_equal activity.messages.size, 11
    assert_predicate activity, :frozen?
    assert_predicate activity.records, :frozen?
  end

  def test_session_values
    session = activity.session

    assert_equal [:running, nil, Time.utc(2026, 3, 14, 7), "Synthetic test run"], [session.sport, session.sub_sport, session.id, session.notes]
    assert_equal Time.utc(2026, 3, 14, 7), activity.start_time
    assert_equal Time.utc(2026, 3, 14, 7, 10, Rational(1, 2)), activity.end_time
    assert_equal "Example Watch", activity.creator[:name]
    assert_equal "Example Exporter", activity.author[:name]
    assert_nil session.multi_sport_session
  end

  def test_session_totals_are_sums_of_stated_lap_values
    assert_in_delta 900.5, activity.total_timer_time
    assert_in_delta 2900.25, activity.total_distance
    assert_equal 210, activity.total_calories
    assert_equal 2, activity.num_laps
  end

  def test_session_maxima_need_every_lap_to_state_them
    # The second lap states no maximum heart rate or speed.
    assert_nil activity.max_heart_rate
    assert_nil activity.max_speed

    xml = Documents.tcx(%(<Activities><Activity Sport="Biking"><Id>2026-01-01T08:00:00Z</Id>
      #{lap('2026-01-01T08:00:00Z', extra: '<MaximumSpeed>9.5</MaximumSpeed><MaximumHeartRateBpm><Value>150</Value></MaximumHeartRateBpm>')}
      #{lap('2026-01-01T08:01:00Z', extra: '<MaximumSpeed>11.0</MaximumSpeed><MaximumHeartRateBpm><Value>149</Value></MaximumHeartRateBpm>')}
    </Activity></Activities>))

    assert_equal [11.0, 150], read(xml).then { |a| [a.max_speed, a.max_heart_rate] }
  end

  def test_session_totals_need_every_lap_to_state_them
    xml = Documents.tcx(%(<Activities><Activity Sport="Other"><Id>2026-01-01T08:00:00Z</Id>
      #{lap('2026-01-01T08:00:00Z')}#{lap('2026-01-01T08:01:00Z', distance: 'oops')}
    </Activity></Activities>))

    assert_nil read(xml).total_distance
    assert_equal 120.0, read(xml).total_timer_time
  end

  def test_values_tcx_does_not_state_are_nil
    %i[total_elapsed_time avg_speed avg_heart_rate avg_cadence max_cadence avg_power max_power
       total_ascent total_descent sub_sport].each do |name|
      assert_nil activity.public_send(name), name
    end
    assert_nil activity.laps.first.total_elapsed_time
    assert_nil activity.records.first.temperature
  end

  def test_lap_values
    first, second = activity.laps

    assert_equal [Time.utc(2026, 3, 14, 7), 600.5, 2000.25, 3.75, 150, 141, 158],
                 [first.start_time, first.total_timer_time, first.total_distance, first.max_speed,
                  first.total_calories, first.avg_heart_rate, first.max_heart_rate]
    assert_equal [:active, :distance, 3.33, 240, 310], [first.intensity, first.trigger_method, first.avg_speed, first.avg_power, first.max_power]
    assert_equal [600.5, 2000.25, nil], [first.timer_time, first.distance, first.elapsed_time]
    assert_equal [:resting, :manual, "  cool  down\n"], [second.intensity, second.trigger_method, second.notes]
    refute_predicate first, :transition?
  end

  def test_lap_cadence_is_the_cadence_element_else_the_running_cadence
    first, second = activity.laps

    assert_equal [85, 90], [first.avg_cadence, first.max_cadence]
    assert_equal [85, 90], [first.avg_run_cadence, first.max_run_cadence]
    assert_equal 80, second.avg_cadence
    assert_nil second.avg_run_cadence
  end

  def test_record_values
    record = activity.records.first

    assert_equal [Time.utc(2026, 3, 14, 7), 12.3456789, -45.6789012, 10.4, 0.0, 120],
                 [record.timestamp, record.latitude, record.longitude, record.altitude, record.distance, record.heart_rate]
    assert_equal [3.1, 84, 84, 250, :footpod, :present],
                 [record.speed, record.cadence, record.run_cadence, record.power, record.cadence_sensor, record.sensor_state]
    assert_equal :trackpoint, record.raw_message.name
    assert_equal 120, record[:heart_rate_bpm]
  end

  def test_invalid_values_are_nil
    assert_nil activity.records.last.heart_rate
    assert_equal "0", activity.records.last.raw_message.field(:heart_rate_bpm).raw_value
  end

  def test_unknown_elements_at_a_known_path_are_not_used
    xml = Documents.trackpoint(%(<Time>2026-01-01T08:00:00Z</Time><Extensions><TPX xmlns="urn:other"><Watts>999</Watts></TPX></Extensions>))

    assert_nil read(xml).records.first.power
  end

  def test_repeated_lap_boundary_trackpoints
    xml = Documents.tcx(%(<Activities><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
      #{lap('2026-01-01T08:00:00Z', points: point('2026-01-01T08:00:00Z') + point('2026-01-01T08:01:00Z', 130))}
      #{lap('2026-01-01T08:01:00Z', points: point('2026-01-01T08:01:00Z', 130) + point('2026-01-01T08:02:00Z'))}
    </Activity></Activities>))
    activity = read(xml)

    assert_equal [0, 60, 120], activity.records.map { |record| record.timestamp.min * 60 }
    assert_equal activity.records, activity.session.records
    assert_equal [2, 2], activity.laps.map { |lap| lap.records.size }
    assert_equal 4, activity.messages.count { |message| message.name == :trackpoint }
  end

  def test_a_repeated_time_with_different_values_is_kept
    xml = Documents.tcx(%(<Activities><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
      #{lap('2026-01-01T08:00:00Z', points: point('2026-01-01T08:00:00Z', 120) + point('2026-01-01T08:00:00Z', 121))}
    </Activity></Activities>))

    assert_equal [120, 121], read(xml).records.map(&:heart_rate)
  end

  def test_multisport_sessions_and_transitions
    xml = Documents.tcx(%(<Activities><MultiSportSession><Id>2026-01-01T08:00:00Z</Id>
      <FirstSport><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>#{lap('2026-01-01T08:00:00Z', points: point('2026-01-01T08:00:00Z'))}</Activity></FirstSport>
      <NextSport>
        <Transition StartTime="2026-01-01T08:01:00Z"><TotalTimeSeconds>30</TotalTimeSeconds><DistanceMeters>0</DistanceMeters><Calories>1</Calories>
          <Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod><Track>#{point('2026-01-01T08:01:10Z')}</Track></Transition>
        <Activity Sport="Biking"><Id>2026-01-01T08:01:30Z</Id>#{lap('2026-01-01T08:01:30Z', time: 600, points: point('2026-01-01T08:02:00Z'))}</Activity>
      </NextSport>
    </MultiSportSession></Activities>))
    activity = read(xml)

    assert_equal %i[running biking], activity.sessions.map(&:sport)
    assert_equal [0, 0], activity.sessions.map(&:multi_sport_session)
    assert_equal 1, activity.multi_sport_sessions.size
    assert_equal 1, activity.transitions.size
    assert_predicate activity.transitions.first, :transition?
    assert_equal 1, activity.transitions.first.records.size
    assert_equal 3, activity.records.size
    assert_equal [60.0, 600.0], activity.sessions.map(&:total_timer_time)
    assert_equal :running, activity.sport
    assert_equal Time.utc(2026, 1, 1, 8, 2), activity.end_time
  end

  def test_course_trackpoints_and_laps_are_not_activity_records
    xml = Documents.tcx(%(<Courses><Course><Name>Loop</Name>
      <Lap><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>1</DistanceMeters><Intensity>Active</Intensity></Lap>
      <Track>#{point('2026-01-01T08:00:00Z')}</Track></Course></Courses>))
    activity = read(xml)

    assert_empty activity.sessions
    assert_empty activity.laps
    assert_empty activity.records
    assert_nil activity.sport
    assert_nil activity.start_time
  end

  def test_an_activity_without_laps
    xml = Documents.tcx(%(<Activities><Activity Sport="Other"><Id>2026-01-01T08:00:00Z</Id></Activity></Activities>))
    activity = read(xml)

    assert_equal [:other, nil, nil, nil, 0], [activity.sport, activity.start_time, activity.end_time, activity.total_timer_time, activity.num_laps]
  end
end
