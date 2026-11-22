# TcxKit — Project Specification

**Status:** Approved by the maintainer on 2026-11-20
**Project type:** Read-only Ruby library for Garmin Training Center XML (TCX) files
**Gem name:** `tcxkit` (free on RubyGems on 2026-11-20)
**Ruby namespace / require path:** `TcxKit` / `require "tcxkit"`
**Ruby support:** 3.1 and newer
**Licence:** MIT

Sister projects: [`fitkit`](https://github.com/scarhand/fitkit) (FIT) and [`gpxkit`](https://github.com/scarhand/gpxkit) (GPX). The three gems expose the same shape of API (section 6.4) so an application can handle all three formats the same way.

## 1. Purpose

Build a reliable, read-only parser for Training Center Database v2 files (`.tcx`), the XML format Garmin introduced with Training Center and that many platforms still export.

The library exposes:

1. A low-level streaming `Reader` that yields one `Message` per meaningful TCX element (trackpoint, lap, activity, ...), keeping every value exactly as written in the file, including elements and extensions the library does not recognise.
2. An optional `Activity` view with sessions, laps and records, in the same shape as `FitKit::Activity`.

The library must not create, modify, rewrite or repair TCX files.

## 2. Goals

- Parse TCX v2 documents according to Garmin's published schema and its Activity Extension v2.
- Stream: memory use must not grow with the number of trackpoints unless the caller keeps them.
- Treat every file as untrusted input: no network access, no external entities, no DTD-defined entities, and enforced limits on size, depth, element count and time.
- Keep the text exactly as it appears in the file next to every typed value.
- Preserve unknown elements, attributes and extensions instead of dropping them.
- Never fill in, estimate, smooth or derive measurements the file does not contain.
- Raise useful, explicit exceptions with line and column numbers.
- One runtime dependency: Nokogiri 1.17 or later, used through its SAX interface.

## 3. Non-goals

- Writing, editing or repairing TCX files.
- XSD validation at runtime. Values are checked against the schema's types, but the document is not rejected for schema violations it can still be read through (section 7).
- Reading `Courses`, `Workouts`, `Folders` or `Author` in depth in the first release. They are recognised and their elements are passed through as generic messages (section 6.2), but they get no convenience API.
- TCX v1 (`TrainingCenterDatabase/v1`).
- Mapping, charting, analysis, unit preferences.

## 4. Reference material

- Training Center Database v2 schema: `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`, published at https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd
- Activity Extension v2 schema: `http://www.garmin.com/xmlschemas/ActivityExtension/v2`, published at https://www8.garmin.com/xmlschemas/ActivityExtensionv2.xsd

Garmin publishes these schemas without stating a licence. **Do not copy them, or parts of them, into this repository.** Implement from reading them, cite the type names in comments and tests, and if XSD validation is ever wanted in tests, fetch the files at test time from Garmin, never at runtime.

Every element, type and range this gem relies on must be checked against the published schema, not taken from memory or inferred from sample files.

## 5. Architecture

Three layers, each usable on its own.

### 5.1 XML layer

- Nokogiri `XML::SAX::Parser#parse_io` over the source IO, wrapped so bytes read are counted (for `max_bytes`) as they are read.
- Keeps an element stack (namespace URI, local name, attributes, line, column) and collects text.
- Rejects unsafe or malformed input (section 7, section 8).
- Knows nothing about laps or trackpoints.

### 5.2 TCX layer

- Recognises the root `TrainingCenterDatabase` in the v2 namespace; anything else raises `UnsupportedFormatError`.
- Decides which elements become messages (section 6.2) and which are fields of the enclosing message.
- Types each field from the schema (section 6.3) and from known extension namespaces.
- Assigns each message its context: which activity, lap and track it belongs to.

### 5.3 Activity layer

- Collects messages into sessions, laps and records (section 6.4).
- Keeps every underlying `Message` reachable (`raw_message`, `messages`).

## 6. Public API

### 6.1 Reader

```ruby
reader = TcxKit::Reader.new("activity.tcx")

reader.each_message do |message|
  case message.name
  when :trackpoint then puts message[:heart_rate_bpm]
  when :lap then puts message[:total_time_seconds]
  end
end
```

Same contract as `FitKit::Reader`:

- `Reader.new(source, close_io: false, source_label: nil, limits: Limits::DEFAULT)`. `source` is a path, a `Pathname` or an IO-like object that responds to `read`. A `Pathname` is read as a path even though it responds to `read`.
- `each_message` streams, and returns an Enumerator without a block.
- Seekable sources can be iterated again; a non-seekable IO can be read once, and a second iteration raises `Error`.
- Caller-owned IO is closed only with `close_io: true`.
- Time spent in the caller's block does not count towards `max_seconds`.

### 6.2 Messages

A message is emitted when its element closes, so it carries everything inside it. As in FIT, a lap's trackpoints therefore arrive before the lap, and an activity's laps arrive before the activity. Elements in the TCX v2 namespace become messages only where the schema puts them:

| Message name | Element (where) | Fields include |
|---|---|---|
| `:trackpoint` | `Trackpoint` (in a `Track`) | `time`, `latitude_degrees`, `longitude_degrees`, `altitude_meters`, `distance_meters`, `heart_rate_bpm`, `cadence`, `sensor_state`, and from `TPX`: `speed`, `run_cadence`, `watts`, `cadence_sensor` |
| `:track` | `Track` (in a lap, transition or course) | none of its own; marks the end of a track |
| `:lap` | `Lap` (in an activity: `ActivityLap_t`; in a course: `CourseLap_t`) | `start_time`, `total_time_seconds`, `distance_meters`, `maximum_speed`, `calories`, `average_heart_rate_bpm`, `maximum_heart_rate_bpm`, `intensity`, `cadence`, `trigger_method`, `notes`, and from `LX`: `avg_speed`, `max_bike_cadence`, `avg_run_cadence`, `max_run_cadence`, `steps`, `avg_watts`, `max_watts` |
| `:transition` | `Transition` (in a multisport `NextSport`) | as `:lap` |
| `:creator` | `Creator` (in an activity or course) | `type` (`xsi:type`), `name`, `unit_id`, `product_id`, `version_major`, `version_minor`, `build_major`, `build_minor` |
| `:activity` | `Activity` (in `Activities`, `FirstSport` or `NextSport`) | `sport`, `id`, `notes`, and from `Training`: `virtual_partner`, `type`, `interval_workout`, `name` |
| `:multi_sport_session` | `MultiSportSession` | `id`, `notes` |
| `:author` | `Author` | `type`, `name`, `version_major` (in `Build`), `lang_id`, `part_number`, ... |
| `:course` | `Course` | `name`, `notes` |
| `:course_point` | `CoursePoint` | `name`, `time`, `latitude_degrees`, `longitude_degrees`, `altitude_meters`, `point_type`, `notes` |
| `:element` | anything else at message level: `Folders`, `Workouts`, the root's `Extensions`, unknown elements | every leaf inside, untyped |
| `:document` | `TrainingCenterDatabase` | the root's attributes (such as `xsi:schemaLocation`); always the last message |

Every leaf element and every attribute inside a message, outside the messages nested in it, is one of its fields. `Activities`, `Courses`, `FirstSport` and `NextSport` only group messages. An element with only attributes (`<TPX CadenceSensor="Bike"/>`) gives only its attribute fields, and an empty `Extensions` element is not a field.

Field names are the local name in snake_case. A `Value` element takes its parent's name (`HeartRateBpm/Value` becomes `heart_rate_bpm`). The path keeps every element: `Position/LatitudeDegrees`, `Extensions/TPX/Speed`, `@StartTime`. Paths use local names only, since prefixes are chosen by each file. When names repeat (`Build/Version/VersionMajor` and `Version/VersionMajor`, or the begin and end positions of a course lap), look fields up by path.

`context` places a message: its own index and its ancestors'. `activity`, `multi_sport_session`, `course`, `author` and `element` count across the document; the others count within their parent (`lap` within its activity, `track` within its lap, `trackpoint` within its track).

```ruby
message.name                  # :trackpoint
message.element_name          # "Trackpoint"
message.context               # { activity: 0, lap: 2, track: 0, trackpoint: 41 }
message.line, message.column  # where the element starts
message.fields                # Array of Field, in document order (names can repeat)
message[:heart_rate_bpm]      # typed value of the first field with that name
message["HeartRateBpm/Value"] # lookup by path
message.field(:heart_rate_bpm)
message.fields_named(:notes)  # every field with that name
message.attributes            # fields for the message element's own attributes
message.timestamp             # the time field, for trackpoints and course points
message.to_h                  # name => value (first of each name)
```

### 6.3 Fields

```ruby
field.name           # :heart_rate_bpm
field.path           # "HeartRateBpm/Value"
field.namespace      # namespace URI of the element or attribute (nil for an unqualified attribute)
field.text           # " 142 ", exactly as written
field.raw_value      # "142": the text after the type's whitespace rule
field.value          # 142, typed; nil when invalid
field.type           # :positive_byte, :double, :date_time, :sport, :token, :string, :unknown, ...
field.known?         # false where the schema does not put this element or attribute
field.valid?
field.invalid_reason # nil, :empty, :not_a_number, :not_finite, :not_an_integer, :out_of_range,
                     # :not_a_date_time, :no_utc_offset, :not_in_enumeration, :not_a_boolean,
                     # :too_short, :too_long, :no_pattern_match
field.line
```

Types come from tables written from the schemas, keyed by path and namespace: `Extensions/TPX/Speed` is typed only when `TPX` and `Speed` are in the Activity Extension v2 namespace, whatever their prefix.

- Whitespace: `xsd:string` (such as `Notes`) keeps the text as written; every other type collapses it (XSD `collapse`), so `raw_value` is the collapsed text.
- `xsd:double` → `Float`. `INF` and `NaN` are not finite (`:not_finite`). Callers that need exact decimals use `BigDecimal(field.raw_value)`.
- Integer types → `Integer`, range-checked: `unsignedShort`, `unsignedInt`, `positiveByte` (1 to 255, heart rates) and `CadenceValue_t` (0 to 254). A decimal such as `142.0` is `:not_an_integer`. Signs follow the XSD 1.1 rule: an optional `+`, and `-` only before zero (`+007` is 7, `-0` is 0, `-1` is `:not_an_integer`). XSD 1.0 allows digits only for the unsigned types; the value is the same either way, so the more lenient rule is kept.
- `xsd:dateTime` → `Time` in UTC when the text has `Z` or an offset. Without an offset the value is `nil` and `invalid_reason` is `:no_utc_offset` (decision 1, section 13). Fractional seconds are kept. Impossible dates and times (February 30, hour 24, second 60, offsets beyond 14 hours) are `:not_a_date_time`.
- `xsd:boolean` → `true` or `false`.
- Enumerations (`Sport_t`, `Intensity_t`, `TriggerMethod_t`, `SensorState_t`, `CadenceSensorType_t`, `BuildType_t`, `TrainingType_t`, `CoursePointType_t`) → `Symbol` in snake_case, spaces included (`First Aid` is `:first_aid`, `4th Category` is `:"4th_category"`). Matching is exact after collapsing whitespace (`Absent`, not `absent`); anything else is `:not_in_enumeration`.
- `Token_t` → the collapsed `String`. Restrictions on its length (in characters) and pattern are validity: `RestrictedToken_t` (`Course/Name`, `Training/Plan/Name`) 1 to 15 characters, `CoursePointName_t` 1 to 10, `LangID_t` exactly 2, `PartNumber_t` the pattern `[\p{Lu}\d]{3}-[\p{Lu}\d]{5}-[\p{Lu}\d]{2}`. Text outside them keeps its `raw_value` with `:too_short`, `:too_long` or `:no_pattern_match`.
- Ranges are validity, not errors: `DegreesLatitude_t` (-90 to 90), `DegreesLongitude_t` (-180 up to, not including, 180).
- Unknown elements and attributes: `known?` false, `type` `:unknown`, `value` is the text as written.

### 6.4 Activity view

The shared shape across fitkit, tcxkit and gpxkit:

```ruby
activity = TcxKit::Activity.read("activity.tcx", limits: { max_seconds: 30 })

activity.sessions   # one per <Activity> element
activity.laps       # every lap, in file order
activity.records    # every trackpoint, in file order
activity.messages   # every Message
activity.session    # first session
activity.creator    # first session's Creator, or nil

activity.sport
activity.start_time
activity.total_timer_time
activity.total_distance
activity.total_calories

record = activity.records.first
record.timestamp    # Time (UTC)
record.latitude     # degrees
record.longitude
record.altitude     # m
record.distance     # m, as stated by the file
record.heart_rate   # bpm
record.cadence      # rpm, the Cadence element
record.run_cadence  # TPX RunCadence, as stated
record.speed        # m/s, TPX Speed
record.power        # W, TPX Watts
record.raw_message

lap = activity.laps.first
lap.start_time
lap.total_timer_time  # TotalTimeSeconds
lap.total_distance    # DistanceMeters
lap.max_speed
lap.total_calories
lap.avg_heart_rate
lap.max_heart_rate
lap.avg_cadence
lap.intensity
lap.trigger_method
lap.avg_speed         # LX
lap.avg_power         # LX AvgWatts
lap.max_power         # LX MaxWatts
lap.records           # this lap's trackpoints
```

Method names match `FitKit::Activity` wherever the meaning matches. A TCX `Lap` has a single `TotalTimeSeconds` and no elapsed time, so `total_elapsed_time` is `nil` instead of borrowing the timer time. Every value is reported in SI units and as the file states it; nothing is computed from positions or timestamps.

`activity.sport` is `:running`, `:biking` or `:other`, the TCX `Sport_t` value. Mapping it to an application's sports is the caller's job.

Session totals: TCX states totals only per lap. See decision 2 in section 13.

## 7. Leniency and strictness

Strict (raise):

- Not well-formed XML, a wrong root element, or the TCX v1 namespace.
- A DTD internal subset, or any entity reference other than the five predefined XML entities and character references (section 8).
- Input cut off before the root element closes (`TruncatedFileError`). libxml2 reports only a message and a position, so a file counts as cut off when the error is on the last line with at most part of one token (no `<` or `>`) after it, and the input starts with `<`. Anything else that is not well-formed is `InvalidFileError`.
- Any limit crossed.

Lenient (keep reading, record it on the field or message):

- Values that do not fit their type or range (`valid?` false).
- Unknown elements, unknown attributes, unknown extension namespaces.
- Elements in an order the schema does not allow, or missing required elements (for example a `Lap` without `TotalTimeSeconds`): the field is simply absent.

Known real-world quirk: some exporters write whitespace before the XML declaration, which is not well-formed XML. The reader skips leading ASCII whitespace before parsing (decision 3, section 13). A UTF-8 byte order mark is accepted as XML allows.

## 8. Security

Files come from users and third parties. The reader must:

- Never access the network or the filesystem beyond the source (Nokogiri's SAX parser does not load external DTDs or entities by default; the reader must not turn that on).
- Raise `UnsafeContentError` on a DTD internal subset (`<!DOCTYPE x [ ... ]>`), which is where entities are declared, before the XML parser sees it. A document type declaration without one is allowed, and its external DTD is never loaded.
- Raise `UnsafeContentError` on any reference to a DTD-declared entity, as a second line of defence. Nokogiri reports these through the SAX `reference` callback (Nokogiri 1.17 and later).
- Enforce `Limits` while reading:
  - `max_bytes` (default 64 MB): bytes read from the source.
  - `max_elements` (default 5,000,000): elements opened.
  - `max_depth` (default 64): element nesting.
  - `max_text_bytes` (default 1 MB): text of one element without child elements, one attribute value, or the prolog before the root element. Text between child elements is not kept and not counted.
  - `max_seconds` (default none): parse time on a monotonic clock, excluding the caller's block.
  - `nil` switches a limit off; `Limits.none` switches all off.
- Never log or include file content in exception messages beyond element names and positions.

## 9. Errors

```
TcxKit::Error                 base; source, line, column
├── InvalidFileError          not well-formed XML
├── UnsupportedFormatError    not a TCX v2 document
├── TruncatedFileError        ended before the root element closed
├── UnsafeContentError        DTD-declared entity
└── LimitExceededError        `limit` names the bound crossed
```

Names match fitkit's where the meaning matches, so an application can map all three gems' errors to the same failure codes.

## 10. Testing

- Minitest, no other development dependencies beyond rake.
- Fixtures are synthetic: built in `test/support` or written by hand, with made-up positions and values. Never commit real activities. Document every fixture in `test/fixtures/README.md`.
- Cover each message, field, type, range and enumeration; unknown elements and extensions; every error and limit; hostile inputs (entity expansion, deep nesting, huge text, truncated files, binary garbage, a FIT file passed by mistake); and IO ownership and re-iteration.
- Assert decoded values, not merely that parsing succeeds.
- Each bug fix gets a regression test.

## 11. Compatibility and packaging

- Ruby 3.1+, CI on 3.1, 3.2, 3.3, 3.4 and 4.0.
- Runtime dependency: `nokogiri ~> 1.17` (1.17 added the SAX `reference` callback).
- Semantic versioning. Publish to RubyGems only after the maintainer approves a release.

## 12. Milestones

- **M0 — Foundation** (this PR): specification, gem skeleton, CI.
- **M1 — Safe streaming reader:** XML layer, `Limits`, errors, root detection, the leniency rules in section 7, security tests.
- **M2 — Messages and fields:** the message table in 6.2, schema typing and ranges in 6.3, Activity Extension v2, unknown preservation.
- **M3 — Activity view:** section 6.4.
- **M4 — Hardening and release:** quirks from real exporters (reproduced synthetically), a benchmark on a 24-hour file, README examples verified, first release on approval.

## 13. Decisions (approved 2026-11-20)

1. **Times without a UTC offset.** The schema's `xsd:dateTime` allows them; their time zone is unknown. Decided: `value` nil, `invalid_reason` `:no_utc_offset`, raw text kept, so the gem never guesses a zone.
2. **Session totals.** TCX has no activity-level totals. Decided: `Session#total_timer_time`, `total_distance` and `total_calories` are the sum of the laps' stated values when every lap states it, otherwise nil; `max_heart_rate` and `max_speed` the largest lap value; averages nil. Documented as sums of stated values.
3. **Whitespace before the XML declaration.** Decided: skip it, as described in section 7.
