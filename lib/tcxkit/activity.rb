# frozen_string_literal: true

module TcxKit
  # Convenience view of a TCX file, in the shape of FitKit::Activity.
  #
  #   activity = TcxKit::Activity.read("activity.tcx", limits: { max_seconds: 30 })
  #   activity.sessions.each { |session| puts session.sport }
  #   activity.records.each { |record| puts record.timestamp }
  #
  # A session is one <Activity> element; a multisport file has several.
  # Values are reported as the file states them, in SI units: nothing is
  # computed from positions or timestamps. Every wrapper keeps its Message
  # (raw_message), and `messages` holds all of them.
  #
  # The summary methods on Activity itself (total_distance, max_heart_rate,
  # ...) read the first session. TCX states totals only per lap; a session's
  # totals are the sums of its laps' stated values (SPECIFICATION.md,
  # decision 2).
  #
  # Garmin repeats the trackpoint at a lap boundary as the last point of one
  # lap and the first of the next. Activity#records and Session#records leave
  # out a trackpoint that repeats the one before it exactly (same time,
  # identical fields); Lap#records and the messages keep every one
  # (decision 4).
  class Activity
    SUMMARY = %i[
      sport sub_sport total_distance total_elapsed_time total_timer_time total_calories
      avg_speed max_speed avg_heart_rate max_heart_rate avg_cadence max_cadence
      avg_power max_power total_ascent total_descent num_laps
    ].freeze

    attr_reader :messages, :sessions, :laps, :transitions, :records, :multi_sport_sessions, :author

    # options are passed to Reader.new, e.g. limits: { max_seconds: 30 }.
    def self.read(source, **options)
      new(Reader.new(source, **options).each_message.to_a)
    end

    def self.from_file(path, **options)
      read(path, **options)
    end

    def self.from_io(io, **options)
      read(io, **options)
    end

    def initialize(messages)
      @messages = messages.freeze
      records_by_lap = Hash.new { |hash, key| hash[key] = [] }
      laps_by_activity = Hash.new { |hash, key| hash[key] = [] }
      creators = {}
      @sessions = []
      @laps = []
      @transitions = []
      @records = []
      @multi_sport_sessions = []
      @author = nil

      @messages.each do |message|
        context = message.context
        case message.name
        when :trackpoint
          next unless context.key?(:activity) || context.key?(:transition)

          record = Record.new(message)
          @records << record unless repeat?(@records.last, record)
          records_by_lap[lap_key(context)] << record
        when :lap
          next unless context.key?(:activity)

          lap = Lap.new(message, records_by_lap.delete(lap_key(context)) || [])
          @laps << lap
          laps_by_activity[context[:activity]] << lap
        when :transition
          @transitions << Lap.new(message, records_by_lap.delete(lap_key(context)) || [])
        when :creator
          creators[context[:activity]] = message if context.key?(:activity)
        when :activity
          index = context[:activity]
          @sessions << Session.new(message, laps_by_activity.delete(index) || [], creators.delete(index))
        when :multi_sport_session then @multi_sport_sessions << message
        when :author then @author ||= message
        end
      end

      [@sessions, @laps, @transitions, @records, @multi_sport_sessions].each(&:freeze)
      freeze
    end

    # The first session, or nil.
    def session
      @sessions.first
    end

    # The first session's Creator message, or nil.
    def creator
      session&.creator
    end

    def start_time
      session&.start_time
    end

    # The last session's last trackpoint time.
    def end_time
      @sessions.last&.end_time
    end

    SUMMARY.each do |name|
      define_method(name) { session&.public_send(name) }
    end

    private

    def repeat?(previous, record)
      self.class.repeat?(previous, record)
    end

    # A trackpoint that repeats the previous one: same time, identical fields.
    def self.repeat?(previous, record)
      return false unless previous && record.timestamp && previous.timestamp == record.timestamp

      previous.raw_message.fields.map { |field| [field.path, field.text] } ==
        record.raw_message.fields.map { |field| [field.path, field.text] }
    end

    # Trackpoints belong to the lap or transition whose context they share.
    def lap_key(context)
      context.key?(:transition) ? [:transition, context[:multi_sport_session], context[:transition]] : [:lap, context[:activity], context[:lap]]
    end

    # Base for the wrappers: typed values by path, ignoring fields the schema
    # does not put there (an unknown element at the same path is not used).
    class Wrapper
      attr_reader :raw_message

      def initialize(message)
        @raw_message = message
      end

      def [](key)
        @raw_message[key]
      end

      private

      def value(path)
        @raw_message.fields.each { |field| return field.value if field.path == path && field.known? }
        nil
      end
    end

    # One <Activity>.
    class Session < Wrapper
      attr_reader :laps, :creator

      def initialize(message, laps, creator)
        super(message)
        @laps = laps.freeze
        @creator = creator
        freeze
      end

      def sport = value("@Sport")
      def sub_sport = nil
      def id = value("Id")
      def notes = value("Notes")

      # Index of the multisport session this activity belongs to, or nil.
      def multi_sport_session
        @raw_message.context[:multi_sport_session]
      end

      # Every lap's trackpoints, leaving out exact repeats at lap boundaries.
      def records
        @laps.flat_map(&:records).each_with_object([]) do |record, records|
          previous = records.last
          records << record unless previous && Activity.repeat?(previous, record)
        end
      end

      # The first lap's StartTime.
      def start_time
        @laps.first&.start_time
      end

      # The time of the last trackpoint with a valid time.
      def end_time
        @laps.reverse_each do |lap|
          lap.records.reverse_each { |record| return record.timestamp if record.timestamp }
        end
        nil
      end

      def num_laps = @laps.size

      # Sums of the laps' stated values, when every lap states one.
      def total_timer_time = sum(:total_timer_time)
      def total_distance = sum(:total_distance)
      def total_calories = sum(:total_calories)

      # The largest of the laps' stated values, when every lap states one.
      def max_heart_rate = largest(:max_heart_rate)
      def max_speed = largest(:max_speed)

      # Not stated by TCX for a whole activity.
      def total_elapsed_time = nil
      def avg_speed = nil
      def avg_heart_rate = nil
      def avg_cadence = nil
      def max_cadence = nil
      def avg_power = nil
      def max_power = nil
      def total_ascent = nil
      def total_descent = nil

      private

      def stated(name)
        values = @laps.map(&name)
        values.empty? || values.include?(nil) ? nil : values
      end

      def sum(name)
        stated(name)&.sum
      end

      def largest(name)
        stated(name)&.max
      end
    end

    # One <Lap> (or a multisport <Transition>).
    class Lap < Wrapper
      attr_reader :records

      def initialize(message, records)
        super(message)
        @records = records.freeze
        freeze
      end

      def transition? = @raw_message.name == :transition
      def start_time = value("@StartTime")
      def total_timer_time = value("TotalTimeSeconds")
      def total_distance = value("DistanceMeters")
      def max_speed = value("MaximumSpeed")
      def total_calories = value("Calories")
      def avg_heart_rate = value("AverageHeartRateBpm/Value")
      def max_heart_rate = value("MaximumHeartRateBpm/Value")
      def intensity = value("Intensity")

      # Cadence as fitkit reports it: the Cadence element (cycling), else
      # the Activity Extension's running cadence. Both are stated values in
      # the same unit FIT uses.
      def avg_cadence = value("Cadence") || avg_run_cadence
      def max_cadence = value("Extensions/LX/MaxBikeCadence") || max_run_cadence
      def trigger_method = value("TriggerMethod")
      def notes = value("Notes")

      # Activity Extension v2 (LX).
      def avg_speed = value("Extensions/LX/AvgSpeed")
      def avg_run_cadence = value("Extensions/LX/AvgRunCadence")
      def max_run_cadence = value("Extensions/LX/MaxRunCadence")
      def steps = value("Extensions/LX/Steps")
      def avg_power = value("Extensions/LX/AvgWatts")
      def max_power = value("Extensions/LX/MaxWatts")

      # A TCX lap has one time, TotalTimeSeconds; no elapsed time is stated.
      def total_elapsed_time = nil
      def total_ascent = nil
      def total_descent = nil
      def sport = nil
      def sub_sport = nil

      # Shorter names kept for FitKit::Lap compatibility.
      def timer_time = total_timer_time
      def distance = total_distance
      def elapsed_time = nil
    end

    # One <Trackpoint>.
    class Record < Wrapper
      def initialize(message)
        super
        freeze
      end

      def timestamp = value("Time")
      def latitude = value("Position/LatitudeDegrees")
      def longitude = value("Position/LongitudeDegrees")
      def altitude = value("AltitudeMeters")
      def distance = value("DistanceMeters")
      def heart_rate = value("HeartRateBpm/Value")
      # The Cadence element (cycling), else TPX RunCadence (running), as
      # fitkit's cadence holds either.
      def cadence = value("Cadence") || run_cadence
      def sensor_state = value("SensorState")

      # Activity Extension v2 (TPX).
      def speed = value("Extensions/TPX/Speed")
      def run_cadence = value("Extensions/TPX/RunCadence")
      def power = value("Extensions/TPX/Watts")
      def cadence_sensor = value("Extensions/TPX/@CadenceSensor")

      # Not in TCX.
      def grade = nil
      def temperature = nil
    end
  end
end
