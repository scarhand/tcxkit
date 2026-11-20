# TcxKit

A read-only, streaming Ruby parser for Garmin Training Center Database v2 (`.tcx`) files.

**Status: milestone M1 of 4.** The reader reads a whole document safely (limits, DTD refusal, truncation detection) and checks it is TCX v2, but yields no messages yet; they arrive in M2. The full API is in [`SPECIFICATION.md`](SPECIFICATION.md).

```ruby
require "tcxkit"

begin
  TcxKit::Reader.new("activity.tcx", limits: { max_seconds: 30 }).each_message { |message| }
rescue TcxKit::TruncatedFileError, TcxKit::InvalidFileError, TcxKit::UnsupportedFormatError,
       TcxKit::UnsafeContentError, TcxKit::LimitExceededError => error
  warn "#{error.class}: #{error.message}" # includes the line and column
end
```

TcxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [gpxkit](https://github.com/scarhand/gpxkit) (GPX), and shares their API shape. Planned for M2 and M3:

```ruby
require "tcxkit"

# Low level: one message per trackpoint, lap, activity, ...
TcxKit::Reader.new("activity.tcx").each_message do |message|
  puts message[:heart_rate_bpm] if message.name == :trackpoint
end

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
