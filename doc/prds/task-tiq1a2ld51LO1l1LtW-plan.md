# Build plan: Mutation-verify the Schema entry-point API

PRD: [task-tiq1a2ld51LO1l1LtW.md](./task-tiq1a2ld51LO1l1LtW.md)

## Goal

Remove the 33 `.mutant.yml` ignore entries covering `OdataDuty::Schema` / `Schema::Metadata`
(class DSL) and `OdataDuty::SchemaBuilder::Schema` (builder DSL), and add public-API tests that
kill every surviving mutation so `bundle exec mutant run <the 33 subjects>` reports **zero
survivors**. No new consumer capability — a test-quality cleanup.

## Diagnosis (run once, up front)

`bundle exec mutant run` over the 33 subjects (with entries temporarily removed) reports **316
alive** mutations. Most are killable by pinning observable output. A handful are *equivalent
mutations* (mutated code has identical observable behaviour given the current feature set) and can
only be killed by **accepting the mutation** — a source simplification with identical output. Those
are called out per task and must be flagged in review (PRD §9).

Equivalent mutations requiring accept-refactors:
- Class DSL `Schema::Metadata#endpoints` = `entity_sets + singletons`, with `#singletons` always
  `[]` (no singleton feature exists). `+ singletons` and `- singletons` are equivalent. Accept:
  simplify `endpoints` to `entity_sets` and delete the now-dead `singletons` method. Only
  `index_hash` / `Schema.endpoints` call it (metadata.xml.erb does not reference `singletons`).
- Builder `SchemaBuilder::Schema#entity_sets` = `all_containers.grep(EntitySet)`; every container is
  an `EntitySet` (only `add_entity_set` populates `@containers`), so `.grep(EntitySet)` is a no-op.
  Accept: `def entity_sets = all_containers`.
- Builder `SchemaBuilder::Schema#complex_types` uses `t.is_a?(ComplexType) && !t.is_a?(EntityType)`;
  since `EntityType < ComplexType` and it is the only subclass, this equals
  `t.instance_of?(ComplexType)`. Accept: `all_types.select { |t| t.instance_of?(ComplexType) }`.

## Hard rules (every task)

- TDD: failing test first, watched to fail for the right reason, then minimal code.
- Public API only — no reaching into internal classes. Follow the existing `spec/odata_duty/oas2/**`
  convention (`OdataDuty::OAS2.build_json(schema, context:)`) when OAS2 output must be asserted, and
  `Schema.metadata_xml` / `index_hash` / `execute` / `.to_mcp_server` for everything else.
- Each task removes **only its slice** of `.mutant.yml` ignore entries, then runs
  `bundle exec mutant run <its subjects>` and drives survivors to zero.
- `bundle exec rake` (RSpec + RuboCop) green before the task is done. 99-char lines, RuboCop metrics.
- Accept-refactors: apply the minimal source change, keep observable output identical, and flag it.

## Tasks

- [x] **Task 1 — Class DSL: `Schema` declarations & metadata renderers.**
  Remove these 19 entries from `.mutant.yml` and kill their survivors with specs under
  `spec/odata_duty/entity_set/**`:
  `Schema.namespace`, `.version`, `.title`, `.base_url`, `.entity_sets`, `.endpoints`,
  `.index_hash`, `.metadata_xml`, `.to_mcp_server`; `Schema::Metadata#namespace`, `#title`,
  `#version`, `#complex_types`, `#entity_types`, `#enum_types`, `#metadata_types`, `#singletons`,
  `#endpoints`, `#check_names`.
  Pin: exact `namespace`/`title`/`version`/`base_url` strings in `$metadata` XML / `index_hash`;
  `entity_sets` `.uniq` dedup (declare a set twice → one container); `metadata_types` `.uniq`
  (two sets sharing a type → one type rendered); each type selector isolates its kind (schema with
  entity + complex + enum types → `$metadata` renders exactly the right elements); `index_hash`
  `@odata.context` equals the passed URL and each endpoint `name`/`kind`/`url`; `to_mcp_server`
  lists the expected tools/resources; `check_names` raises `"Duplicate <Name> type"` on a dup and
  does not on a clean schema.
  **Accept-refactor:** simplify `Schema::Metadata#endpoints` to `entity_sets` and delete the dead
  `singletons` method (flag it). Files: `lib/odata_duty.rb`, `spec/odata_duty/entity_set/**`.
  Depends on: none.

- [x] **Task 2 — Class DSL: `Schema` request dispatch.**
  Remove `Schema.execute`, `.create`, `.update`, `.delete` from `.mutant.yml`; kill survivors with
  specs under `spec/odata_duty/entity_set/**`. Pin GET dispatch (same URL family → `Users`
  collection, `Users(1)` individual, `Users/$count` count, each a distinct asserted result);
  `create` returns the created entity (POST), `update` partial-merges (PATCH), `delete` removes
  (DELETE) — assert observable effect and returned payload; default `query_options: {}` matters
  (calling without it behaves; a required/`nil` default would raise/misbehave); argument pass-through
  (dropping `url:`/`context:`/`schema:` breaks routing); error classes propagate
  (`ResourceNotFoundError`, `NoImplementationError`, `InvalidQueryOptionError` / `InvalidValue`).
  Files: `lib/odata_duty.rb` (only if an accept-refactor is needed — likely none),
  `spec/odata_duty/entity_set/**`. Depends on: Task 1 (shares schemas/fixtures patterns).

- [x] **Task 3 — Builder DSL: `SchemaBuilder::Schema` structure & introspection.**
  Remove `SchemaBuilder::Schema#initialize`, `#inspect`, `#all_containers`, `#complex_types`,
  `#entity_sets`, `#individual_entity_sets` from `.mutant.yml`; kill survivors with specs under
  `spec/odata_duty/schema_builder/**`. Pin: `initialize` freezes each of
  `namespace`/`host`/`scheme`/`base_path`/`base_url` (assert `.frozen?` on the public attr_readers),
  clones inputs (a mutable string passed in is not frozen/mutated afterward), coerces via `to_str`
  (a Symbol input raises `NoMethodError`), and defaults `host` to `localhost` (build without `host`
  → `base_url` starts `https://localhost`); `inspect` string contains the class name, `@namespace`,
  `@base_path`, container **names** (keys), and type **names** (keys); `all_containers` sorts by
  name (declare two out of alpha order → sorted); `entity_sets`/`complex_types`/
  `individual_entity_sets` return the right subsets, observed via `$metadata` and
  `OdataDuty::OAS2.build_json(schema, context:)` (a set whose resolver defines `individual` gets an
  individual path; one that doesn't, doesn't).
  **Accept-refactors:** `entity_sets` → `all_containers`; `complex_types` →
  `all_types.select { |t| t.instance_of?(ComplexType) }` (flag both). Files:
  `lib/odata_duty/schema_builder.rb`, `spec/odata_duty/schema_builder/**`. Depends on: none.

- [x] **Task 4 — Builder DSL: `SchemaBuilder::Schema` request dispatch.**
  Remove `SchemaBuilder::Schema#execute`, `#create`, `#update`, `#delete` from `.mutant.yml`; kill
  survivors with specs under `spec/odata_duty/schema_builder/**`. Same dispatch/effect/default/
  pass-through/error assertions as Task 2, but through the builder DSL (real `SetResolver`
  subclasses referenced by string name). Files: `lib/odata_duty/schema_builder.rb` (accept-refactor
  unlikely), `spec/odata_duty/schema_builder/**`. Depends on: Task 3.

- [x] **Task 5 — Documentation: update the ratchet count.**
  In `spec/using_mutant.md`, update the "shrunk that list to 80 entries" figure to reflect the 33
  removals (→ 47). No `doc/` guide changes and no `CLAUDE.md` Features entry (PRD §8: no new
  consumer capability). Depends on: Tasks 1–4 (all removals landed).
