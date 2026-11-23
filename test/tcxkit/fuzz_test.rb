# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/fuzzer"

# Whatever the input, reading either succeeds or raises a TcxKit::Error:
# never another exception. FUZZ_ITERATIONS and FUZZ_SEED run longer or
# different rounds; a failure names the seed and iteration to reproduce it.
class FuzzTest < Minitest::Test
  ITERATIONS = Integer(ENV.fetch("FUZZ_ITERATIONS", "300"))
  SEED = Integer(ENV.fetch("FUZZ_SEED", "20261123"))

  DOCUMENTS = [
    File.read(Documents.fixture("activity.tcx"), encoding: "UTF-8"),
    Documents.tcx(%(<Activities><MultiSportSession><Id>2026-01-01T08:00:00Z</Id><FirstSport><Activity Sport="Running">
      <Id>2026-01-01T08:00:00Z</Id><Lap StartTime="2026-01-01T08:00:00Z"><TotalTimeSeconds>1</TotalTimeSeconds>
      <DistanceMeters>1</DistanceMeters><Calories>1</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
      </Lap></Activity></FirstSport></MultiSportSession></Activities><Courses><Course><Name>Loop</Name><CoursePoint>
      <Name>Turn</Name><Time>2026-01-01T08:00:00Z</Time><Position><LatitudeDegrees>1</LatitudeDegrees>
      <LongitudeDegrees>2</LongitudeDegrees></Position><PointType>Left</PointType></CoursePoint></Course></Courses>))
  ].freeze

  def test_mutated_documents_only_raise_tcxkit_errors
    fuzzer = Fuzzer.new(SEED)
    outcomes = Hash.new(0)
    limits = { max_bytes: 1_000_000, max_elements: 20_000, max_depth: 64, max_text_bytes: 100_000, max_seconds: 5 }

    ITERATIONS.times do |iteration|
      document = fuzzer.mutate(DOCUMENTS[iteration % DOCUMENTS.size])
      begin
        activity = TcxKit::Activity.from_io(StringIO.new(document), limits: limits)
        exercise(activity)
        outcomes[:read] += 1
      rescue TcxKit::Error => error
        outcomes[error.class] += 1
      rescue StandardError, SystemStackError => error
        flunk "FUZZ_SEED=#{SEED} iteration #{iteration}: #{error.class}: #{error.message}\n#{document.inspect[0, 2000]}"
      end
    end

    # Both outcomes occur, so the mutations neither always break nor never break the document.
    assert_operator outcomes[:read], :>, 0
    assert_operator outcomes.sum { |outcome, count| outcome == :read ? 0 : count }, :>, 0
    warn "fuzz outcomes: #{outcomes.transform_keys { |key| key.to_s.delete_prefix('TcxKit::') }}" if ENV["FUZZ_VERBOSE"]
  end

  def test_mutated_values_only_raise_tcxkit_errors
    fuzzer = Fuzzer.new(SEED)
    read = 0

    ITERATIONS.times do |iteration|
      document = fuzzer.mutate_values(DOCUMENTS[iteration % DOCUMENTS.size])
      begin
        exercise(TcxKit::Activity.from_io(StringIO.new(document)))
        read += 1
      rescue TcxKit::Error
        nil
      rescue StandardError, SystemStackError => error
        flunk "FUZZ_SEED=#{SEED} iteration #{iteration}: #{error.class}: #{error.message}\n#{document[0, 3000]}"
      end
    end

    # Values are fuzzed, not the markup, so nearly every document still reads.
    assert_operator read, :>, ITERATIONS / 2
  end

  private

  # Touches every value, so lazy work and wrappers run too.
  def exercise(activity)
    activity.messages.each { |message| message.fields.each { |field| [field.value, field.valid?, field.raw_value] } }
    activity.records.each { |record| [record.timestamp, record.latitude, record.cadence, record.power] }
    activity.laps.each { |lap| [lap.total_timer_time, lap.avg_cadence, lap.max_cadence] }
    TcxKit::Activity::SUMMARY.each { |name| activity.public_send(name) }
    [activity.start_time, activity.end_time]
  end
end
