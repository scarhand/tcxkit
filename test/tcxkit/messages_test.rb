# frozen_string_literal: true

require_relative "../test_helper"

class MessagesTest < Minitest::Test
  def messages
    @messages ||= TcxKit::Reader.new(Documents.fixture("activity.tcx")).each_message.to_a
  end

  def named(name)
    messages.select { |message| message.name == name }
  end

  def test_messages_arrive_when_their_element_closes
    assert_equal %i[trackpoint trackpoint track lap trackpoint track lap creator activity author document],
                 messages.map(&:name)
  end

  def test_context_places_each_message
    assert_equal [{ activity: 0, lap: 0, track: 0, trackpoint: 0 }, { activity: 0, lap: 0, track: 0, trackpoint: 1 },
                  { activity: 0, lap: 1, track: 0, trackpoint: 0 }], named(:trackpoint).map(&:context)
    assert_equal [{ activity: 0, lap: 0 }, { activity: 0, lap: 1 }], named(:lap).map(&:context)
    assert_equal({ activity: 0, creator: 0 }, named(:creator).first.context)
    assert_equal({ author: 0 }, named(:author).first.context)
    assert_equal({}, named(:document).first.context)
  end

  def test_trackpoint_fields
    point = named(:trackpoint).first

    assert_equal Time.utc(2026, 3, 14, 7), point[:time]
    assert_equal Time.utc(2026, 3, 14, 7), point.timestamp
    assert_in_delta 12.3456789, point[:latitude_degrees]
    assert_in_delta(-45.6789012, point[:longitude_degrees])
    assert_in_delta 10.4, point[:altitude_meters]
    assert_in_delta 0.0, point[:distance_meters]
    assert_equal 120, point[:heart_rate_bpm]
    assert_equal :present, point[:sensor_state]
  end

  def test_activity_extension_v2_trackpoint_fields
    point = named(:trackpoint).first

    assert_in_delta 3.1, point[:speed]
    assert_equal 84, point[:run_cadence]
    assert_equal 250, point[:watts]
    assert_equal :footpod, point[:cadence_sensor]
    assert_equal TcxKit::ACTIVITY_EXTENSION_NAMESPACE, point.field(:speed).namespace
    assert_equal "Extensions/TPX/Speed", point.field(:speed).path
  end

  def test_lap_fields_and_activity_extension_v2_lap_fields
    lap = named(:lap).first

    assert_equal Time.utc(2026, 3, 14, 7), lap[:start_time]
    assert_in_delta 600.5, lap[:total_time_seconds]
    assert_in_delta 2000.25, lap[:distance_meters]
    assert_in_delta 3.75, lap[:maximum_speed]
    assert_equal 150, lap[:calories]
    assert_equal 141, lap[:average_heart_rate_bpm]
    assert_equal 158, lap[:maximum_heart_rate_bpm]
    assert_equal :active, lap[:intensity]
    assert_equal :distance, lap[:trigger_method]
    assert_in_delta 3.33, lap[:avg_speed]
    assert_equal [85, 90, 240, 310], lap.to_h.values_at(:avg_run_cadence, :max_run_cadence, :avg_watts, :max_watts)
    assert_equal Time.utc(2026, 3, 14, 7, 10, Rational(1, 2)), named(:lap).last[:start_time]
  end

  def test_activity_creator_and_author
    activity = named(:activity).first
    creator = named(:creator).first
    author = named(:author).first

    assert_equal :running, activity[:sport]
    assert_equal Time.utc(2026, 3, 14, 7), activity[:id]
    assert_equal "Synthetic test run", activity[:notes]
    assert_equal [false, :workout, true, "Intervals"], activity.to_h.values_at(:virtual_partner, :type, :interval_workout, :name)
    assert_equal ["Device_t", "Example Watch", 1_234_567_890, 1, 2, 10],
                 creator.to_h.values_at(:type, :name, :unit_id, :product_id, :version_major, :version_minor)
    assert_equal [:release, "en", "000-00000-00"], [author["Build/Type"], author[:lang_id], author[:part_number]]
  end

  def test_message_element_attributes
    assert_equal [:start_time], named(:lap).first.attributes.map(&:name)
    assert_equal [:sport], named(:activity).first.attributes.map(&:name)
  end

  def test_unknown_extensions_are_kept
    field = named(:trackpoint)[1].field(:mystery)

    refute_predicate field, :known?
    assert_equal :unknown, field.type
    assert_equal "42", field.value
    assert_equal "urn:example:unknown", field.namespace
  end

  def test_invalid_values_are_kept_with_a_reason
    field = named(:trackpoint).last.field(:heart_rate_bpm)

    refute_predicate field, :valid?
    assert_nil field.value
    assert_equal "0", field.raw_value
    assert_equal :out_of_range, field.invalid_reason
  end

  def test_string_text_is_kept_exactly
    notes = named(:lap).last.field(:notes)

    assert_equal "  cool  down\n", notes.text
    assert_equal "  cool  down\n", notes.value
  end

  def test_document_message_keeps_root_attributes
    document = named(:document).first

    assert_equal "TrainingCenterDatabase", document.element_name
    assert_equal [:schema_location], document.fields.map(&:name)
  end

  def test_lookups
    point = named(:trackpoint).first

    assert_equal 120, point["HeartRateBpm/Value"]
    assert_nil point[:missing]
    assert_equal 1, point.fields_named(:heart_rate_bpm).size
    assert_raises(ArgumentError) { point[0] }
    assert_predicate point, :frozen?
    assert_predicate point.fields.first, :frozen?
  end
end
