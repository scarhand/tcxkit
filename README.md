# TcxKit

A read-only, streaming Ruby parser for Garmin Training Center Database v2 (`.tcx`) files.

**Status: specification only.** Nothing is parsed yet. The planned API is in [`SPECIFICATION.md`](SPECIFICATION.md); the README will show working examples once milestone M1 lands.

TcxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [gpxkit](https://github.com/scarhand/gpxkit) (GPX), and shares their API shape:

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
