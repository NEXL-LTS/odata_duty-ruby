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
- **`$search`** — AND/OR/NOT grammar via `od_search`; also drives the MCP search tool — `doc/using_search.md`.
- **Paging** — `$top`/`$skip` and server-driven `@odata.nextLink` via `od_next_link_skiptoken`.
- **Computed properties** — `doc/using_computed.md`.
- **Property mutability** — `mutability: :immutable`/`:non_insertable`/`:computed` per property (create/update settability + `Core` annotations & `Capabilities.InsertRestrictions`; `$oas2` per-operation `<Entity>Create`/`<Entity>Update` request bodies) — `doc/using_mutability.md`.
- **Init args** — pass per-request data into `od_after_init` — `doc/using_init_args.md`.
- **MCP server** — tools/resources over JSON-RPC — `doc/using_mcp.md`, `doc/mcp_crash_course.md`.
- **Rails generators** — `install` and `entity_set` — `doc/entity_set_generator.md`.

## Commands

- `bundle exec rake` — full suite: RSpec **and** RuboCop. This is what CI runs (and it runs `rake` four times to surface flaky tests). Also measures and enforces 100% line + branch coverage via SimpleCov — see `doc/using_coverage.md`. Run this before considering work done.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb` — single file.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb:42` — single example by line.
- `bundle exec rubocop` / `bundle exec rubocop -A` — lint / autocorrect.
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
- **`MCPExecutor`** (`mcp_executor.rb`) handles JSON-RPC (`Schema.handle_jsonrpc`): `initialize`, `resources/list`, `resources/templates/list`, `resources/read`, `tools/list`, `tools/call`. It reuses `Executor` under the hood — OData query options are simply forwarded. A `search_<EntitySet>` tool is exposed only for entity sets whose resolver defines `od_search`.
- **Renderers**: `EdmxSchema` (`metadata_xml` via `lib/metadata.xml.erb`, `index_hash`) and `OAS2` (`oas2.rb` + `oas2/*_path.rb`) produce the `$metadata`, index, and `$oas2` documents.
- **`*Wrapper` classes** isolate user-supplied objects: `ContextWrapper` (per-request context + URL helpers), `CreateComplexTypeHashWrapper` (coerces/validates POST bodies into typed input), `dynamic_object_wrapper.rb.erb` / `mapper_builder.rb` (build per-entity object→hash mappers from property definitions).
- **`parslet_search_expression.rb`** parses the `$search` grammar (AND/OR/NOT/terms) into an expression object passed to a resolver's `od_search`.

## The `od_*` convention

User code communicates with the framework through methods/hooks prefixed `od_`, looked up dynamically:

- `od_after_init` — runs after the set/resolver is constructed; typically loads `@records`. Can take positional or keyword args (see `set_resolver.rb` and `doc/using_init_args.md`).
- `collection`, `individual(id)`, `count` — read operations; `create(input)`, `update(id, input)`, `delete(id)` — write operations (see `doc/using_create_update_and_delete.md`). A missing one raises `NoImplementationError` (the framework rescues `NoMethodError` to detect absence).
- `od_filter_eq/ne/gt/lt(property_name, value)` — narrow results per `$filter`.
- `od_search(expression)` — enables `$search` and the MCP search tool.
- `od_next_link_skiptoken` — drives server-driven paging `@odata.nextLink`.

When editing, prefer extending these conventions over adding new public API surface.

## Conventions

- **The source code is the best source of truth.** Read it before relying on docs, comments, or this file — when they disagree, the code wins. Keep prose (docs, comments) minimal and let the code speak.
- **Prefer single-line comments.** Avoid multi-line comment blocks in source code; if something needs more than one line of explanation, rename/refactor or move the explanation into `doc/`.
- Tests must use only the gem's **public API** — do not test internal classes/methods directly (`AGENTS.md`).
- Two-space indent, **99-char line limit**, Ruby 3 syntax. RuboCop metrics are tightened (see `.rubocop.yml`: `MethodLength` 13, `ClassLength`/`ModuleLength` 99, `AbcSize` 30) — keep methods small rather than adding inline disables.
- Update `doc/` guides and `README.md` when external usage changes; bump `spec.version` in `odata_duty.gemspec` for releases.

## Rails integration

Optional, loaded via `railtie.rb` only when Rails is present. Generators under `lib/generators/odata_duty/`: `install` (controller + schema boilerplate) and `entity_set` (entity type, set/resolver, specs, AR concern). See `doc/entity_set_generator.md`. The controller wires `$metadata`, `$oas2`, GET (`schema.execute`), and POST (`schema.create`) — see the README's Rails example.
