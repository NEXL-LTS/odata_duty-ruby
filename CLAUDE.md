# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`odata_duty` is a Ruby gem (no Rails required) for defining structured data and operations once in a Ruby DSL, then exposing them as an [OData](doc/odata_crash_course.md) v4 service. From a single schema it generates: EDMX `$metadata` XML, an OData index document, OAS2/Swagger JSON, and an [MCP](doc/mcp_crash_course.md) server over JSON-RPC. Ruby 3.2+ is required.

## Features

Short index of what's implemented; see the linked `doc/` guide for the full contract. **Keep this list current** — see `/build` for when to update it.

- **Read** — `collection`, `individual(id)`, `/$count`.
- **Write** — `create` (POST), `update` (PATCH, partial-merge), `delete` (DELETE); each inferred from method presence and reflected in `$oas2`, `$metadata` capability annotations, and MCP tools — `doc/using_create_update_and_delete.md`.
- **`$filter`** — `od_filter_eq/ne/gt/lt` — `doc/using_filter.md`.
- **`$select`** — `doc/using_select.md`.
- **`$search`** — AND/OR/NOT grammar via `od_search`; also adds `$search` to the MCP `list_/count_<Set>` tools — `doc/using_search.md`.
- **Paging** — `$top`/`$skip` and server-driven `@odata.nextLink` via `od_next_link_skiptoken`.
- **Computed properties** — `doc/using_computed.md`.
- **Property mutability** — `mutability: :immutable`/`:non_insertable`/`:computed` per property (create/update settability + `Core` annotations & `Capabilities.InsertRestrictions`; `$oas2` per-operation `<Entity>Create`/`<Entity>Update` request bodies) — `doc/using_mutability.md`.
- **Descriptions** — `description:` on schema, entity/complex/enum type, enum member, property (incl. `property_ref`), and entity set; renders into `$metadata` (`Core.Description`), `$oas2` (`info`/definitions/properties/operation `summary`+`description`), and MCP (tool descriptions, input-schema property descriptions, server `instructions`) — `doc/using_descriptions.md`.
- **Init args** — pass per-request data into `od_after_init` — `doc/using_init_args.md`.
- **Request context** — the `context` object in resolver hooks (delegation, `od_full_url`, `query_options`, `base_url`, `current`), plus `od_context`/`object` in class-DSL property methods — `doc/using_context.md`.
- **MCP server** — tools-only over JSON-RPC; reads inferred as `list_/get_/count_<Set>` tools, writes as `create_/update_/delete_<Set>`, no resources — `doc/using_mcp.md`, `doc/mcp_crash_course.md`.
- **Rails generators** — `install` and `entity_set` — `doc/entity_set_generator.md`.

## Commands

- `bundle exec rake` — full suite: RSpec **and** RuboCop. This is what CI runs (and it runs `rake` four times to surface flaky tests). Also measures and enforces 100% line + branch coverage via SimpleCov — see `spec/using_coverage.md`. Run this before considering work done.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb` — single file.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb:42` — single example by line.
- `bundle exec rubocop` / `bundle exec rubocop -A` — lint / autocorrect.
- `bundle exec mutant run --since main` — mutation-test only the code your branch touched; CI runs this on PRs and **fails on any surviving mutation**. Pre-existing debt is ignore-listed in `.mutant.yml` (a ratchet: never add entries, remove them as you touch those methods) — see `spec/using_mutant.md`.
- `foreman start` (see `Procfile`) — runs the dev server (`rackup spec/config.ru` with reload via `rerun`) plus the MCP inspector. `spec/config.ru` is a full working Rack app demonstrating REST + MCP/SSE endpoints; treat it as the canonical integration example.
- `ruby bin/test_generator.rb` — exercises the Rails entity-set generator against a temp dir without a full Rails app.

## Two parallel DSLs — keep both in sync

There are **two ways to define a schema**, and most features must be implemented in both:

1. **Class-based DSL** (`lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`): subclass `OdataDuty::EntityType`, `OdataDuty::EntitySet`, `OdataDuty::Schema`. The entity set itself implements the data methods (`collection`, `individual`, `create`).
2. **Builder DSL** (`lib/odata_duty/schema_builder.rb` + `schema_builder/*`): `OdataDuty::SchemaBuilder.build(namespace:, host:, scheme:, base_path:) { |s| ... }` constructs the schema at runtime (e.g. from `request` data in a controller). Data logic lives in a separate `OdataDuty::SetResolver` subclass referenced by string name via `resolver:`.

This split is mirrored in the specs: `spec/odata_duty/entity_set/**` covers the class DSL, `spec/odata_duty/schema_builder/**` covers the builder DSL, often with near-identical test cases. **When adding or changing a feature, update both DSLs and both spec trees.**

## Architecture / request flow

A schema is just metadata until executed. Both DSLs expose `__metadata` objects that the renderers and executor walk.

- **`Executor`** (`executor.rb`) is the core of GET. It resolves a URL to an endpoint, instantiates the set builder/resolver, then dispatches on the URL/query: `(id)` → individual, `/$count` → count, otherwise collection. It applies `$filter` (→ `od_filter_eq/ne/gt/lt`, see `filter.rb`), `$select` (`doc/using_select.md`), `$search` (`doc/using_search.md`), `$top`/`$skip` paging. `Schema.execute` / `.create` delegate here.
- **`McpServerBuilder`** (`mcp_server_builder.rb`, with input schemas in `mcp_input_schemas.rb`) builds a tools-only `MCP::Server` from the schema (`schema.to_mcp_server`); the SDK handles the JSON-RPC (`initialize`, `tools/list`, `tools/call`). Reads are exposed as tools inferred from the read hooks: `list_<Set>` (from `collection`), `count_<Set>` (from `count`), and `get_<Set>` (from `individual`); writes as `create_/update_/delete_<Set>`. Every tool reuses `Executor` under the hood — OData query options are forwarded. `$search` is folded into `list_<Set>`/`count_<Set>` only for sets whose resolver defines `od_search`. No MCP resources are registered (the server advertises only the `tools` capability).
- **Renderers**: `EdmxSchema` (`metadata_xml` via `lib/metadata.xml.erb`, `index_hash`) and `OAS2` (`oas2.rb` + `oas2/*_path.rb`) produce the `$metadata`, index, and `$oas2` documents.
- **`*Wrapper` classes** isolate user-supplied objects: `ContextWrapper` (per-request context + URL helpers), `CreateComplexTypeHashWrapper` (coerces/validates POST bodies into typed input), `dynamic_object_wrapper.rb.erb` / `mapper_builder.rb` (build per-entity object→hash mappers from property definitions).
- **`parslet_search_expression.rb`** parses the `$search` grammar (AND/OR/NOT/terms) into an expression object passed to a resolver's `od_search`.

## The `od_*` convention

User code communicates with the framework through methods/hooks prefixed `od_`, looked up dynamically:

- `od_after_init` — runs after the set/resolver is constructed; typically loads `@records`. Can take positional or keyword args (see `set_resolver.rb` and `doc/using_init_args.md`).
- `collection`, `individual(id)`, `count` — read operations; `create(input)`, `update(id, input)`, `delete(id)` — write operations (see `doc/using_create_update_and_delete.md`). A missing one raises `NoImplementationError` (the framework rescues `NoMethodError` to detect absence).
- `od_filter_eq/ne/gt/lt(property_name, value)` — narrow results per `$filter`.
- `od_search(expression)` — enables `$search` (in OData and on the MCP `list_/count_<Set>` tools).
- `od_next_link_skiptoken` — drives server-driven paging `@odata.nextLink`.

When editing, prefer extending these conventions over adding new public API surface.

## Conventions

- **The source code is the best source of truth.** Read it before relying on docs, comments, or this file — when they disagree, the code wins. Keep prose (docs, comments) minimal and let the code speak.
- **Prefer single-line comments.** Avoid multi-line comment blocks in source code; if something needs more than one line of explanation, rename/refactor or move the explanation into `doc/`.
- **Tests must use only the gem's public API.** The public surface is: the schema-definition DSL (class macros / builder methods) and the errors it raises at definition time; `Schema.execute`/`.create`/`.update`/`.delete` (or the builder equivalents) and the JSON/XML they produce; `metadata_xml`/`index_hash`; `OAS2.build_json`; and `to_mcp_server` plus its JSON-RPC calls (`initialize`, `tools/list`, `tools/call`). Never test internal classes/methods directly — common traps: `__metadata`, any `*Wrapper`/`Endpoint` object, or calling `.to_oas2`/`.to_value`/`.mapper` on a type/property object directly. A DSL macro's own reader (e.g. `PersonEntity.description`) is not proof a value propagated — assert against the rendered output (`$metadata`/`$oas2`/MCP) instead. This is enforced by the `OdataDuty/PublicApiOnly` RuboCop cop — see `spec/using_public_api_only.md`.
- **Tests are public documentation.** Write specs as human-readable usage examples: real named classes and schemas defined the way a consumer would write them, exercised through the public API, with descriptions explaining the case each example helps with. No stubbing (`stub_const`, mocks) of gem internals — enforced by the `OdataDuty/PublicApiOnly` cop; if a behavior can only be shown with test machinery, question the behavior instead. The tests ARE the documentation: convey intent through `describe`/`it` descriptions, not explanatory `#` comments in spec files.
- Two-space indent, **99-char line limit**, Ruby 3 syntax. RuboCop metrics are tightened (see `.rubocop.yml`: `MethodLength` 13, `ClassLength`/`ModuleLength` 99, `AbcSize` 30) — keep methods small rather than adding inline disables.
- Update `doc/` guides and `README.md` when external usage changes; bump `spec.version` in `odata_duty.gemspec` for releases.

## Pull requests

Keep the PR description simple and high level — a short summary of what changed and why, not a
task-by-task walkthrough or exhaustive file list. Details belong in the commits.

## Rails integration

Optional, loaded via `railtie.rb` only when Rails is present. Generators under `lib/generators/odata_duty/`: `install` (controller + schema boilerplate) and `entity_set` (entity type, set/resolver, specs, AR concern). See `doc/entity_set_generator.md`. The controller wires `$metadata`, `$oas2`, GET (`schema.execute`), and POST (`schema.create`) — see the README's Rails example.
