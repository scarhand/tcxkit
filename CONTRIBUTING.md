# Contributing

1. Read [`SPECIFICATION.md`](SPECIFICATION.md). Check every element, type and range against Garmin's published schema, not memory or sample files.
2. Work one milestone at a time, in small pull requests.
3. Add tests that assert decoded values, error classes and positions. Every bug fix gets a regression test.
4. Run `bundle exec rake test` before opening a pull request.
5. Fixtures are synthetic, with made-up positions and values. Document each one in `test/fixtures/README.md`.
6. Do not copy Garmin's XSD files, or parts of them, into the repository.
7. Keep the README honest about what works and what is planned.
