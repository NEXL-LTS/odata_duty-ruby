# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.31.0] - 2026-08-16

### Added
- `description:` keyword/macro on every schema element — schema, entity/complex/enum type,
  enum member, property (including `property_ref`), and entity set — in both the class-based
  and builder DSLs. Descriptions render into `$metadata` (`Core.Description` annotations),
  `$oas2` (`info`, definitions, properties, operation `summary`/`description`), and MCP
  (tool descriptions, input-schema property descriptions, server `instructions`) (#63).
- Build-time MCP identifier validation: `to_mcp_server` now raises
  `OdataDuty::InvalidMcpIdentifierError` before returning a server if a generated tool name
  or input-schema property key would violate the Anthropic Messages API's identifier
  constraints — non-ASCII or oversized property names, oversized entity-set-derived tool
  names, or a property colliding with a reserved `odata_*` key (#62).

### Changed
- **Breaking (MCP tool shape):** the MCP tools' OData query-option arguments are renamed
  from `$filter`, `$select`, `$search`, `$top`, and `$skip` to `odata_filter`,
  `odata_select`, `odata_search`, `odata_top`, and `odata_skip`. `$`-prefixed keys violate
  the Anthropic Messages API's tool-schema identifier pattern and previously broke
  `tools/list` for any Claude-based MCP client. The OData HTTP endpoints are unaffected —
  they still use the standard `$`-prefixed query options (#62).

### Documentation
- New `doc/using_descriptions.md`; `doc/using_mcp.md` and `doc/using_oas2.md` updated for
  descriptions and the new MCP argument names.

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

[Unreleased]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.31.0...HEAD
[0.31.0]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.30.1...v0.31.0
[0.30.1]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.4...v0.30.0
[0.21.4]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.3...v0.21.4
[0.21.3]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.21.0...v0.21.3
[0.21.0]: https://github.com/NEXL-LTS/odata_duty-ruby/compare/v0.20.1...v0.21.0
