# TcxKit

A read-only, streaming Ruby parser for Garmin Training Center Database v2 (`.tcx`) files.

**Status: milestone M2 of 4.** The reader streams typed messages for every trackpoint, lap, activity and the rest of a TCX v2 document. The `Activity` view arrives in M3. The full API is in [`SPECIFICATION.md`](SPECIFICATION.md).

```ruby
require "tcxkit"

TcxKit::Reader.new("activity.tcx", limits: { max_seconds: 30 }).each_message do |message|
  case message.name
  when :trackpoint
    puts [message.timestamp, message[:latitude_degrees], message[:longitude_degrees], message[:heart_rate_bpm]].inspect
  when :lap
    puts "lap #{message.context[:lap]}: #{message[:total_time_seconds]} s, #{message[:distance_meters]} m"
  end
end
```

Every value is a `Field` with the text as written, a typed value, and a reason when the value does not fit the schema:

```ruby
field = message.field(:heart_rate_bpm)
field.text            # "0"
field.value           # nil
field.invalid_reason  # :out_of_range (heart rates are 1 to 255)
```

Errors carry the line and column:

```ruby
rescue TcxKit::TruncatedFileError, TcxKit::InvalidFileError, TcxKit::UnsupportedFormatError,
       TcxKit::UnsafeContentError, TcxKit::LimitExceededError => error
```

TcxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [gpxkit](https://github.com/scarhand/gpxkit) (GPX), and shares their API shape. The activity view is planned for M3:

```ruby
require "tcxkit"

# Activity view: sessions, laps and records
activity = TcxKit::Activity.read("activity.tcx")
activity.records.each { |record| puts [record.timestamp, record.latitude, record.longitude].inspect }
```

## Principles

- Read-only: never writes or repairs files.
- Untrusted input: no network access, no DTD entities, enforced limits on size, depth and time.
- Values exactly as written next to typed values; unknown elements and extensions kept.
- Nothing filled in, estimated or smoothed.

## Development

```sh
bundle install
bundle exec rake test
```

Requires Ruby 3.1 or newer. The only runtime dependency is Nokogiri.

Test fixtures must be synthetic. Never commit real activity files: they contain locations, times and health data.

## Licence

MIT, see [`LICENSE`](LICENSE). Garmin's TCX schemas are not part of this repository.
