# Changelog

## Unreleased

- M2: messages and fields. The Reader yields a `Message` per trackpoint, track, lap, transition, creator, activity, multisport session, author, course and course point (plus generic `:element` messages and a final `:document`), each with its `context`. Every leaf element and attribute is a `Field` with the text as written, a value typed from the TCX v2 and Activity Extension v2 schemas, and `valid?`/`invalid_reason`. Unknown elements and extensions are kept as untyped fields.
- M1: safe streaming reader. `Reader` (paths, Pathnames and IO, `close_io:`, re-reading seekable IO), `Limits` (`max_bytes`, `max_elements`, `max_depth`, `max_text_bytes`, `max_seconds`), refusal of DTD internal subsets and DTD entities, `TruncatedFileError` for files cut off, `UnsupportedFormatError` for anything but TCX v2, and skipping whitespace before the XML declaration. Yields no messages yet. Requires Nokogiri 1.17.
- M0: specification, gem skeleton and CI.
