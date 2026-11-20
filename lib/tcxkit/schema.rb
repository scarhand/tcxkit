# frozen_string_literal: true

module TcxKit
  # Field types per message, written from Garmin's published schemas
  # TrainingCenterDatabase v2 and ActivityExtension v2 (type names in
  # comments). The schemas themselves are not part of this repository.
  #
  # Keys are paths relative to the message element. A segment in the TCX v2
  # namespace is its local name, one in the Activity Extension v2 namespace
  # is "ax2:" plus its local name, an attribute is "@" plus its name (an
  # xsi attribute "@xsi:" plus its name). A path with a segment in any other
  # namespace never matches, so an element is only typed where the schema
  # puts it.
  module Schema
    T = Types

    DEGREES_LATITUDE = T.double(:degrees_latitude, min: -90.0, max: 90.0) # DegreesLatitude_t
    DEGREES_LONGITUDE = T.double(:degrees_longitude, min: -180.0, max_exclusive: 180.0) # DegreesLongitude_t
    POSITIVE_BYTE = T.integer(:positive_byte, min: 1, max: 255) # HeartRateInBeatsPerMinute_t/Value
    CADENCE_VALUE = T.integer(:cadence_value, min: 0, max: 254) # CadenceValue_t
    UNSIGNED_SHORT = T.integer(:unsigned_short, min: 0, max: 65_535)
    UNSIGNED_INT = T.integer(:unsigned_int, min: 0, max: 4_294_967_295)

    SPORT = T.enumeration(:sport, %w[Running Biking Other])
    INTENSITY = T.enumeration(:intensity, %w[Active Resting])
    TRIGGER_METHOD = T.enumeration(:trigger_method, %w[Manual Distance Location Time HeartRate])
    SENSOR_STATE = T.enumeration(:sensor_state, %w[Present Absent])
    CADENCE_SENSOR_TYPE = T.enumeration(:cadence_sensor_type, %w[Footpod Bike])
    BUILD_TYPE = T.enumeration(:build_type, %w[Internal Alpha Beta Release])
    TRAINING_TYPE = T.enumeration(:training_type, %w[Workout Course])

    VERSION = {
      "VersionMajor" => UNSIGNED_SHORT, "VersionMinor" => UNSIGNED_SHORT,
      "BuildMajor" => UNSIGNED_SHORT, "BuildMinor" => UNSIGNED_SHORT
    }.freeze

    def self.within(prefix, table)
      table.transform_keys { |key| "#{prefix}/#{key}" }
    end

    # Trackpoint_t, with ActivityTrackpointExtension_t (TPX).
    TRACKPOINT = {
      "Time" => T.date_time,
      "Position/LatitudeDegrees" => DEGREES_LATITUDE,
      "Position/LongitudeDegrees" => DEGREES_LONGITUDE,
      "AltitudeMeters" => T.double,
      "DistanceMeters" => T.double,
      "HeartRateBpm/Value" => POSITIVE_BYTE,
      "Cadence" => CADENCE_VALUE,
      "SensorState" => SENSOR_STATE,
      "Extensions/ax2:TPX/ax2:Speed" => T.double,
      "Extensions/ax2:TPX/ax2:RunCadence" => CADENCE_VALUE,
      "Extensions/ax2:TPX/ax2:Watts" => UNSIGNED_SHORT,
      "Extensions/ax2:TPX/@CadenceSensor" => CADENCE_SENSOR_TYPE
    }.freeze

    # ActivityLap_t, with ActivityLapExtension_t (LX).
    ACTIVITY_LAP = {
      "@StartTime" => T.date_time,
      "TotalTimeSeconds" => T.double,
      "DistanceMeters" => T.double,
      "MaximumSpeed" => T.double,
      "Calories" => UNSIGNED_SHORT,
      "AverageHeartRateBpm/Value" => POSITIVE_BYTE,
      "MaximumHeartRateBpm/Value" => POSITIVE_BYTE,
      "Intensity" => INTENSITY,
      "Cadence" => CADENCE_VALUE,
      "TriggerMethod" => TRIGGER_METHOD,
      "Notes" => T.string,
      "Extensions/ax2:LX/ax2:AvgSpeed" => T.double,
      "Extensions/ax2:LX/ax2:MaxBikeCadence" => CADENCE_VALUE,
      "Extensions/ax2:LX/ax2:AvgRunCadence" => CADENCE_VALUE,
      "Extensions/ax2:LX/ax2:MaxRunCadence" => CADENCE_VALUE,
      "Extensions/ax2:LX/ax2:Steps" => UNSIGNED_SHORT,
      "Extensions/ax2:LX/ax2:AvgWatts" => UNSIGNED_SHORT,
      "Extensions/ax2:LX/ax2:MaxWatts" => UNSIGNED_SHORT
    }.freeze

    # CourseLap_t.
    COURSE_LAP = {
      "TotalTimeSeconds" => T.double,
      "DistanceMeters" => T.double,
      "BeginPosition/LatitudeDegrees" => DEGREES_LATITUDE,
      "BeginPosition/LongitudeDegrees" => DEGREES_LONGITUDE,
      "BeginAltitudeMeters" => T.double,
      "EndPosition/LatitudeDegrees" => DEGREES_LATITUDE,
      "EndPosition/LongitudeDegrees" => DEGREES_LONGITUDE,
      "EndAltitudeMeters" => T.double,
      "AverageHeartRateBpm/Value" => POSITIVE_BYTE,
      "MaximumHeartRateBpm/Value" => POSITIVE_BYTE,
      "Intensity" => INTENSITY,
      "Cadence" => CADENCE_VALUE
    }.freeze

    # Activity_t, with Training_t, QuickWorkout_t and Plan_t.
    ACTIVITY = {
      "@Sport" => SPORT,
      "Id" => T.date_time,
      "Notes" => T.string,
      "Training/@VirtualPartner" => T.boolean,
      "Training/QuickWorkoutResults/TotalTimeSeconds" => T.double,
      "Training/QuickWorkoutResults/DistanceMeters" => T.double,
      "Training/Plan/@Type" => TRAINING_TYPE,
      "Training/Plan/@IntervalWorkout" => T.boolean,
      "Training/Plan/Name" => T.token
    }.freeze

    # AbstractSource_t, as Device_t or Application_t (named by xsi:type).
    SOURCE = {
      "@xsi:type" => T.token,
      "Name" => T.token,
      "UnitId" => UNSIGNED_INT,
      "ProductID" => UNSIGNED_SHORT,
      "Build/Type" => BUILD_TYPE,
      "Build/Time" => T.token,
      "Build/Builder" => T.token,
      "LangID" => T.token,
      "PartNumber" => T.token
    }.merge(within("Version", VERSION), within("Build/Version", VERSION)).freeze

    # MultiSportSession_t.
    MULTI_SPORT_SESSION = { "Id" => T.date_time, "Notes" => T.string }.freeze

    # Course_t and CoursePoint_t.
    COURSE = { "Name" => T.token, "Notes" => T.string }.freeze
    COURSE_POINT = {
      "Name" => T.token,
      "Time" => T.date_time,
      "Position/LatitudeDegrees" => DEGREES_LATITUDE,
      "Position/LongitudeDegrees" => DEGREES_LONGITUDE,
      "AltitudeMeters" => T.double,
      "PointType" => T.token,
      "Notes" => T.string
    }.freeze

    EMPTY = {}.freeze

    # The table for a message kind; laps differ inside a course.
    def self.table(kind, context)
      case kind
      when :trackpoint then TRACKPOINT
      when :lap then context.key?(:course) ? COURSE_LAP : ACTIVITY_LAP
      when :transition then ACTIVITY_LAP
      when :activity then ACTIVITY
      when :creator, :author then SOURCE
      when :multi_sport_session then MULTI_SPORT_SESSION
      when :course then COURSE
      when :course_point then COURSE_POINT
      else EMPTY
      end
    end
  end
end
