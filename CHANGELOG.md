# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.30.1] - 2026-08-02

### Added
- `CHANGELOG.md` and a `changelog_uri` gem metadata entry.
- `spec.homepage` and `spec.license = 'MIT'` in the gemspec.

### Fixed
- Gemspec metadata: `homepage_uri` and `source_code_uri` were previously discarded
  because `spec.metadata` was reassigned after being set; all entries are now merged
  into a single hash.
- `spec.files` now references the packaged files that actually exist (`LICENSE`,
  `CHANGELOG.md`) instead of a non-existent `LICENSE.txt`.

## [0.30.0] - 2026-08-02

### Added
- Expose MCP read operations as tools in a tools-only server: `list_/get_/count_<Set>`
  inferred from the read hooks (#60).
- CORS header on the `$oas2` endpoint for Power Automate compatibility (#58).

## [0.21.4] - 2026-07-26

### Changed
- Mutation-tested and hardened the Schema entry-point API, `Executor`, `$oas2` renderer,
  `$search` parser, entity keys, enum types, and the builder DSL; shrank the `.mutant.yml`
  ratchet accordingly (#50–#56, #59).

### Documentation
- Documented nested mutability and typed-input accessor errors (#47).

## [0.21.3] - 2026-07-05

### Added
- Mutation testing with `mutant`; fixed recursive-type crashes it surfaced (#46).

### Documentation
- Documented the SimpleCov coverage workflow (#45).

## [0.21.0] - 2026-06-30

### Added
- `:non_insertable` property mutability value (#43).

### Documentation
- Documented per-operation `$oas2` request bodies (#44).
- Documented the `mutability:` axis and `:immutable` (#42).

## Earlier releases

See the [git tags](https://github.com/NEXL-LTS/odata_duty-ruby/tags) for the history of
releases prior to 0.21.0.

[Unreleased]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.30.1...HEAD
[0.30.1]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.4...v0.30.0
[0.21.4]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.3...v0.21.4
[0.21.3]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.0...v0.21.3
[0.21.0]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.20.1...v0.21.0
