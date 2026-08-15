# Build plan — A runtime spec guard that raises on non-public-API access

PRD: [public-api-runtime-guard.md](./public-api-runtime-guard.md)

## Nature of this PRD

This is **contributor tooling that lives entirely under `spec/`**. It adds no DSL surface and
changes no `$metadata`/`$oas2`/OData JSON/MCP output, and does **not** modify `lib/`. The usual
"implement in both DSLs" rule does not apply to production code here — instead, the guard runs over
the *whole* suite (both DSL spec trees) globally, and the migration touches specs under **both**
`spec/odata_duty/entity_set/**` (class DSL) and `spec/odata_duty/schema_builder/**` (builder DSL).

Because the guard is under `spec/`, it is **not** coverage- or mutation-enforced (SimpleCov already
`add_filter '/spec/'`; mutant runs only over touched `lib/`). It still ships with its own spec.

## Key design notes carried into the tasks

- **Mechanism:** one global `TracePoint(:call)`. Handler: (1) fast-exit unless `tp.defined_class`
  is a gem class; (2) return if `tp.method_id` is on that class's allowlist row; (3) else raise
  `OdataDuty::NonPublicApiError` only when the immediate `caller_locations` frame is a `_spec.rb`
  file. `NonPublicApiError` is defined in the spec-support file, **not** in `lib/`.
- **Owner keying + singleton classes:** key on the *defining* class (`tp.defined_class`), not the
  receiver. Class-DSL DSL/output methods (`OdataDuty::Schema.metadata_xml`, `.namespace`, …) are
  singleton methods, so `defined_class` is `#<Class:OdataDuty::Schema>`; the guard must resolve a
  singleton class to its `attached_object` (Ruby 3.2+ `Class#attached_object`) to find the row.
- **Class-DSL dual-purpose methods:** `namespace`/`version`/`title`/`description`/`entity_sets`/
  `base_url` are the class-DSL *definition* methods called inside `class < OdataDuty::Schema` /
  `Class.new(OdataDuty::Schema)` fixture bodies **and** read back in a few assertions. They are the
  documented DSL surface, so they must be on the class-DSL `Schema` allowlist row (otherwise every
  fixture definition raises). Consequently the guard cannot catch the class-DSL *reader* misuse of
  these — that is an accepted limitation. The guard's real catch is on the **builder** DSL, where
  readers (`schema.types`, `schema.entity_types`, `schema.namespace`, `schema.base_url`) are
  distinct internal instance methods.
- **The allowlist in the PRD table is a starting point.** The real rows are finalised in Task 2 by
  turning the guard on and reading its runtime failures. Expect rows the table omits but the suite
  needs: class-DSL `EntitySet` singleton DSL methods (`entity_type`, `name`, `url`, `description`),
  the request-context object's documented methods (`base_url`, `od_full_url`, `query_options`, …),
  and any base-class instance methods a fixture legitimately calls (e.g. `context`,
  `od_next_link_skiptoken`). Each addition is a reviewed contract decision.
- **Migration:** for each genuine internal-reader access the guard surfaces, either (default)
  migrate the assertion to rendered output (`metadata_xml`/`build_json`/`execute`) or (explicitly,
  per method) promote the reader to the allowlist row **and** document it. Known starting hits:
  builder `schema.types` (×4), `schema.entity_types` (×1), `schema.namespace`/`base_url`
  (schema_structure_spec), plus whatever else runtime surfaces.

## Files

- Guard: `spec/support/public_api_guard.rb` (new) — `OdataDuty::NonPublicApiError`, allowlist data,
  TracePoint install/uninstall.
- Guard spec: `spec/support/public_api_guard_spec.rb` (new).
- Global install: `spec/spec_helper.rb`.
- Migration: spec files under `spec/odata_duty/**` in both trees (discovered at runtime).
- Docs: `spec/using_public_api_only.md`, `CLAUDE.md`.

## Tasks

- [x] **Task 1 — Build the guard and its own spec (uninstalled).**
  Create `spec/support/public_api_guard.rb` defining `OdataDuty::NonPublicApiError < StandardError`
  and a module (e.g. `PublicApiGuard`) that: holds the frozen per-class allowlist map (keyed by gem
  class/module, starting from the PRD table); exposes install/uninstall of a single
  `TracePoint(:call)`; in the handler fast-exits unless `tp.defined_class` (resolving singleton →
  `attached_object`) maps to a gem class in the map, returns if `tp.method_id` is allowlisted, and
  otherwise raises `NonPublicApiError` **only** when the immediate caller frame is a `_spec.rb`
  file. The error message must name the class and method and point at rendered output — e.g.
  `` `types` is not part of the public API of OdataDuty::SchemaBuilder::Schema. Assert on rendered
  output (metadata_xml/build_json/execute) instead. `` Create
  `spec/support/public_api_guard_spec.rb` that requires the guard, installs it **scoped to each
  example** (so this task stays green without touching the rest of the suite), and covers every
  bullet from the PRD's *The guard's spec* section: internal builder method (`types`) raises; a
  documented method (`execute`) accepted; a `SearchExpression`/`SearchTerm` allowlisted method
  accepted and a non-allowlisted one raised; a consumer-subclass fixture accessor accepted; a gem
  self-call driven via `execute` **not** raised (caller-awareness); `inspect`/`to_s` accepted; and
  that the message names the class and method. Do **not** require/install the guard from
  `spec_helper` in this task — keep it uninstalled so `bundle exec rake` stays green in isolation.
  The guard's spec must itself pass `OdataDuty/PublicApiOnly` (use only public constants and plain
  method names — do not name `Executor`; drive the internal-method case via builder `schema.types`).
  PRD excerpt: *Mechanism*, *The guarded-receiver rule*, *The guard's spec*, *Common error cases*.

- [x] **Task 2 — Install the guard globally, finalise the allowlist, and migrate the suite (one
  jointly-green commit).**
  Require and install the guard once from `spec/spec_helper.rb` (a single global interceptor, no
  per-file `using`, no per-example opt-in). Run `bundle exec rake`; the suite will go red. Working
  **from the guard's real runtime failures** (not a grep), for each failure decide: (a) it is the
  documented DSL/entry-point/context surface → add the method to the owning class's allowlist row
  (a reviewed contract addition — expect class-DSL `EntitySet` DSL methods, the request-context
  object's `base_url`/`od_full_url`/`query_options`, base-class `context`, etc.); or (b) it is a
  genuine internal-reader access in a spec → migrate that assertion to rendered output
  (`metadata_xml`/`build_json`/`execute`), which is the default and the strictly-better
  documentation. Resolve the known builder-DSL internal reads (`schema.types` ×4,
  `schema.entity_types`, builder `schema.namespace`/`base_url`) and every other one the guard
  surfaces. **Measure suite wall-clock before and after** the global install and report it; if the
  overhead is unacceptable, fall back to enabling the TracePoint around each example or narrowing to
  gem source files, and surface the tradeoff. Finish on a fully green `bundle exec rake` (RSpec +
  RuboCop, 100% coverage). PRD excerpt: *External API*, *Behavior & expected I/O* (*Raises* /
  *Accepted* / *Not guarded* / *Migrating the existing suite*), *Coverage / performance*, *Scope*.

- [x] **Task 3 — Contributor documentation.**
  Update `spec/using_public_api_only.md` with a section on the runtime guard: what it catches that
  the cop cannot (internal methods on real gem objects), that it complements rather than replaces
  the cop (the strong/weak split), how to respond to a `NonPublicApiError` (assert on rendered
  output, or promote a method to the allowlist as a reviewed contract change), and where the
  per-class allowlist lives. Update `CLAUDE.md` so the "Tests must use only the gem's public API"
  convention notes two-layered enforcement: the RuboCop cop for name/mock/bypass leaks and the
  runtime guard for internal-method access on gem objects. **No `## Features` entry** — this is
  contributor tooling, not a consumer capability. PRD excerpt: *Documentation impact*.
