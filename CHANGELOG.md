# Changelog

## 0.1.0

First release: a read-only, streaming reader for Garmin Training Center Database v2 files, with typed messages and fields, enforced limits, refusal of DTDs, and an `Activity` view in the shape of `FitKit::Activity`. Requires Ruby 3.1 and Nokogiri 1.17.

Development, by milestone:

- M4: hardening. Reading 24-hour files is about 25% faster (the time limit's clock now pauses once per message, and paths, names and types are cached per place in a message). Seeded fuzz tests of bytes, markup and values run with the suite. Exporter quirks are reproduced in tests; undeclared namespace prefixes no longer stop reading (decision 6), a DTD in a UTF-16 document is refused before parsing, and numbers beyond a Float are decoded without Ruby warnings.
- M3: `Activity` view in the shape of `FitKit::Activity`: sessions (one per `<Activity>`), laps, transitions and records, with the session totals of decision 2. Checked against FIT exports of the same activities; `cadence` reports running cadence from the Activity Extension when `Cadence` is absent (decision 4), and the Activity's records leave out exact repeats of lap boundary trackpoints (decision 5).
- Fields typed with the schema's length, pattern and enumeration restrictions that M2 left out: `RestrictedToken_t` (course and plan names, 1 to 15 characters), `CoursePointName_t` (1 to 10), `CoursePointType_t` (an enumeration), `LangID_t` (2 characters) and `PartNumber_t` (a pattern). New invalid reasons `:too_short`, `:too_long` and `:no_pattern_match`. Accepting `+` and `-0` on unsigned integers (the XSD 1.1 rule) is now documented.
- M2: messages and fields. The Reader yields a `Message` per trackpoint, track, lap, transition, creator, activity, multisport session, author, course and course point (plus generic `:element` messages and a final `:document`), each with its `context`. Every leaf element and attribute is a `Field` with the text as written, a value typed from the TCX v2 and Activity Extension v2 schemas, and `valid?`/`invalid_reason`. Unknown elements and extensions are kept as untyped fields.
- M1: safe streaming reader. `Reader` (paths, Pathnames and IO, `close_io:`, re-reading seekable IO), `Limits` (`max_bytes`, `max_elements`, `max_depth`, `max_text_bytes`, `max_seconds`), refusal of DTD internal subsets and DTD entities, `TruncatedFileError` for files cut off, `UnsupportedFormatError` for anything but TCX v2, and skipping whitespace before the XML declaration. Yields no messages yet. Requires Nokogiri 1.17.
- M0: specification, gem skeleton and CI.
