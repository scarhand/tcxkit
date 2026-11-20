# Changelog

## Unreleased

- M1: safe streaming reader. `Reader` (paths, Pathnames and IO, `close_io:`, re-reading seekable IO), `Limits` (`max_bytes`, `max_elements`, `max_depth`, `max_text_bytes`, `max_seconds`), refusal of DTD internal subsets and DTD entities, `TruncatedFileError` for files cut off, `UnsupportedFormatError` for anything but TCX v2, and skipping whitespace before the XML declaration. Yields no messages yet. Requires Nokogiri 1.17.
- M0: specification, gem skeleton and CI.
