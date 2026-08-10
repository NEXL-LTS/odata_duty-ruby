# AGENTS.md

Guidance for AI coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

## What this is

`odata_duty` is a Ruby gem (no Rails required) for defining structured data and operations once in a
Ruby DSL, then exposing them as an [OData](doc/odata_crash_course.md) v4 service. From a single
schema it generates: EDMX `$metadata` XML, an OData index document, OAS2/Swagger JSON, and an
[MCP](doc/mcp_crash_course.md) server over JSON-RPC. Ruby 3.2+ is required.

## Features

Short index of what's implemented; see the linked `doc/` guide for the full contract. **Keep this
list current** — see `/build` for when to update it.

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

- `bundle exec rake` — full suite: RSpec **and** RuboCop. This is what CI runs (and it runs `rake` four times to surface flaky tests). Also measures and enforces 100% line + branch coverage via SimpleCov — see `doc/using_coverage.md`. Run this before considering work done.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb` — single file.
- `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb:42` — single example by line.
- `bundle exec rubocop` / `bundle exec rubocop -A` — lint / autocorrect.
- `bundle exec mutant run --since main` — mutation-test only the code your branch touched; CI runs this on PRs and **fails on any surviving mutation** — see `spec/using_mutant.md`.
- `foreman start` (see `Procfile`) — runs the dev server (`rackup spec/config.ru` with reload via `rerun`) plus the MCP inspector. `spec/config.ru` is a full working Rack app demonstrating REST + MCP/SSE endpoints; treat it as the canonical integration example.
- `ruby bin/test_generator.rb` — exercises the Rails entity-set generator against a temp dir without a full Rails app.

## Universal rules

- **The source code is the best source of truth.** Read it before relying on docs, comments, or
  this file — when they disagree, the code wins.
- **Two-space indent, 99-char lines, Ruby 3 syntax.** RuboCop metrics are tightened (`.rubocop.yml`:
  `MethodLength` 13, `ClassLength`/`ModuleLength` 99, `AbcSize` 30) — split the method rather than
  adding an inline disable.
- **Keep PR descriptions short and high level** — what changed and why, not a task-by-task
  walkthrough or a file list. Details belong in the commits.

## Scoped conventions

Everything else lives in [`doc/conventions/`](doc/conventions/), delivered just-in-time by
[agent-apropos](https://github.com/NEXL-LTS/agent-apropos): path-scoped rules arrive when you edit a
matching file, construct-scoped rules when you write matching code, and workflow skills when the
task calls for them. Run `agent-apropos generate` after editing any convention doc.
