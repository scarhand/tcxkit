# TcxKit — Project Specification

**Status:** Draft for review
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
- One runtime dependency: Nokogiri, used through its SAX interface.

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

- `Reader.new(source, close_io: false, source_label: nil, limits: Limits::DEFAULT)`. `source` is a path, a `Pathname` or an IO-like object that responds to `read`.
- `each_message` streams, and returns an Enumerator without a block.
- Seekable sources can be iterated again; a non-seekable IO can be read once, and a second iteration raises `Error`.
- Caller-owned IO is closed only with `close_io: true`.
- Time spent in the caller's block does not count towards `max_seconds`.

### 6.2 Messages

A message is emitted when its element closes, so it carries everything inside it. As in FIT, a lap's trackpoints therefore arrive before the lap, and an activity's laps arrive before the activity.

| Message name | Element | Fields include |
|---|---|---|
| `:trackpoint` | `Trackpoint` | `time`, `latitude_degrees`, `longitude_degrees`, `altitude_meters`, `distance_meters`, `heart_rate_bpm`, `cadence`, `sensor_state`, and from `TPX`: `speed`, `run_cadence`, `watts` (attribute `cadence_sensor`) |
| `:track` | `Track` | none of its own; marks the end of a track |
| `:lap` | `Lap` | `start_time` (attribute), `total_time_seconds`, `distance_meters`, `maximum_speed`, `calories`, `average_heart_rate_bpm`, `maximum_heart_rate_bpm`, `intensity`, `cadence`, `trigger_method`, `notes`, and from `LX`: `avg_speed`, `max_bike_cadence`, `avg_run_cadence`, `max_run_cadence`, `steps`, `avg_watts`, `max_watts` |
| `:creator` | `Creator` | `name`, `unit_id`, `product_id`, `version_major`, `version_minor`, `build_major`, `build_minor`, and the `xsi:type` attribute |
| `:activity` | `Activity` | `sport` (attribute), `id`, `notes` |
| `:multi_sport_session` | `MultiSportSession` | `id`, `notes` |
| `:author` | `Author` | `name`, `build_*`, `lang_id`, `part_number` |
| `:element` | anything else at message level (courses, workouts, folders, unknown) | every child, generically |
| `:document` | `TrainingCenterDatabase` | none of its own; the last message |

Field names are the element's local name in snake_case. A `Value` child takes its parent's name (`HeartRateBpm/Value` becomes `heart_rate_bpm`), and a wrapper such as `Position` or `Extensions/TPX` is dropped from the name but kept in the path.

```ruby
message.name                 # :trackpoint
message.context              # { activity: 0, lap: 2, track: 0, trackpoint: 41 }
message.line                 # line of the opening tag
message.fields               # Array of Field, in document order (names can repeat)
message[:heart_rate_bpm]     # typed value of the first field with that name
message["HeartRateBpm/Value"] # lookup by path
message.field(:heart_rate_bpm)
message.fields_named(:notes) # every field with that name
message.attributes           # attributes of the message element itself, as Fields
message.to_h                 # name => value (first of each name)
```

### 6.3 Fields

```ruby
field.name           # :heart_rate_bpm
field.path           # "HeartRateBpm/Value"
field.namespace      # TCX v2 or Activity Extension v2 namespace URI
field.raw_value      # "142", exactly as written (whitespace collapsed per its XSD type)
field.value          # 142, typed; nil when invalid
field.type           # :unsigned_byte, :double, :date_time, :token, :string, ...
field.known?         # false for elements this gem does not know
field.valid?         # false when raw_value does not fit the type or its range
field.invalid_reason # nil, :not_a_number, :out_of_range, :no_utc_offset, :not_in_enumeration, ...
field.line
```

Typing:

- `xsd:double` → `Float`. Callers that need exact decimals use `BigDecimal(field.raw_value)`.
- `xsd:unsignedByte`, `unsignedShort`, `unsignedInt` → `Integer`, range-checked.
- `xsd:dateTime` → `Time` in UTC when the text has `Z` or an offset. Without an offset the value is `nil` and `invalid_reason` is `:no_utc_offset` (see open question 1). Fractional seconds are kept.
- Enumerations (`Sport_t`, `Intensity_t`, `TriggerMethod_t`, `SensorState_t`, `CadenceSensorType_t`) → `Symbol` in snake_case; a value outside the enumeration keeps its text, `value` is nil and `invalid_reason` is `:not_in_enumeration`.
- Schema ranges are enforced as validity, not errors: `DegreesLatitude_t` (-90..90), `DegreesLongitude_t` (-180..180), `HeartRateInBeatsPerMinute_t` (≥ 1), `CadenceValue_t` (≤ 254) and the like, each checked against the published schema.
- Unknown elements: `known?` false, `type` `:string`, `value` is the text.

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

Session totals: TCX states totals only per lap. See open question 2.

## 7. Leniency and strictness

Strict (raise):

- Not well-formed XML, a wrong root element, or the TCX v1 namespace.
- Any entity reference other than the five predefined XML entities and character references (section 8).
- Input cut off before the root element closes (`TruncatedFileError`).
- Any limit crossed.

Lenient (keep reading, record it on the field or message):

- Values that do not fit their type or range (`valid?` false).
- Unknown elements, unknown attributes, unknown extension namespaces.
- Elements in an order the schema does not allow, or missing required elements (for example a `Lap` without `TotalTimeSeconds`): the field is simply absent.

Known real-world quirk: some exporters write whitespace before the XML declaration, which is not well-formed XML. The reader skips leading ASCII whitespace before parsing (see open question 3). A UTF-8 byte order mark is accepted as XML allows.

## 8. Security

Files come from users and third parties. The reader must:

- Never access the network or the filesystem beyond the source (Nokogiri's SAX parser does not load external DTDs or entities by default; the reader must not turn that on).
- Raise `UnsafeContentError` on the first reference to an entity declared in a DTD. Nokogiri reports these through the SAX `reference` callback, after libxml2 has expanded internal ones, so the `max_text_bytes` and `max_bytes` limits must still hold during expansion.
- Enforce `Limits` while reading:
  - `max_bytes` (default 64 MB): bytes read from the source.
  - `max_elements` (default 5,000,000): elements opened.
  - `max_depth` (default 64): element nesting.
  - `max_text_bytes` (default 1 MB): text and attribute length of one element.
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
- Runtime dependency: `nokogiri ~> 1.16`.
- Semantic versioning. Publish to RubyGems only after the maintainer approves a release.

## 12. Milestones

- **M0 — Foundation** (this PR): specification, gem skeleton, CI.
- **M1 — Safe streaming reader:** XML layer, `Limits`, errors, root detection, the leniency rules in section 7, security tests.
- **M2 — Messages and fields:** the message table in 6.2, schema typing and ranges in 6.3, Activity Extension v2, unknown preservation.
- **M3 — Activity view:** section 6.4.
- **M4 — Hardening and release:** quirks from real exporters (reproduced synthetically), a benchmark on a 24-hour file, README examples verified, first release on approval.

## 13. Open questions

1. **Times without a UTC offset.** The schema's `xsd:dateTime` allows them; their time zone is unknown. Proposed: `value` nil, `invalid_reason` `:no_utc_offset`, raw text kept, so the gem never guesses a zone.
2. **Session totals.** TCX has no activity-level totals. Proposed: `Session#total_timer_time`, `total_distance` and `total_calories` are the sum of the laps' stated values when every lap states it, otherwise nil; `max_heart_rate` and `max_speed` the largest lap value; averages nil. Documented as sums of stated values.
3. **Whitespace before the XML declaration.** Proposed: skip it, as described in section 7.
