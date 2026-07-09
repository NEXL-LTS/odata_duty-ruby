# Build plan — Retire the `$oas2` renderer mutation-testing debt

PRD: [task-thwgca1mt0SXPjZZWj.md](./task-thwgca1mt0SXPjZZWj.md)

## Context / decisions

- This is a **spec-hardening** PRD: no `$oas2` output changes. The 38 `OdataDuty::OAS2*`
  entries in `.mutant.yml` survive only because every existing `$oas2` spec is anchored to
  `RSpec.describe OdataDuty::EntitySet` / `OdataDuty::SchemaBuilder`, so mutant never selects
  them for the `OdataDuty::OAS2*` subjects. Fix = re-anchor every `OAS2.build_json` example
  group to `RSpec.describe OdataDuty::OAS2, '<feature>'` (mutant prefix-matches nested subjects
  like `OAS2::CollectionPostPath`) + a full-document pin, then delete the 38 entries.
- `$oas2` is **builder-DSL only** (needs `host`/`scheme`/`base_path`). The "mirror both DSL
  trees" rule does **not** apply here — every spec builds via `OdataDuty::SchemaBuilder.build`.
- New consolidated home: `spec/odata_duty/oas2/**`, all groups under `RSpec.describe OdataDuty::OAS2`.
- `Context` test helper = `Struct.new(:endpoint)` from `spec/spec_helper.rb`.
- **No-regression rule:** re-anchoring is spec-only (no lib change) so CI's `mutant --since main`
  can't see it. Each task that removes entries must run scoped `bundle exec mutant run` over the
  affected `OdataDuty::OAS2*` subjects and show zero survivors; the consolidation task must also
  run `'OdataDuty::EntitySet*'` and `'OdataDuty::SchemaBuilder*'` and show zero *new* alive.
- CLAUDE.md `## Features`: internal test-hardening, nothing consumer-observable changes → no
  Features entry. Optional one README line noting `OAS2.build_json` needs a builder-DSL schema.

## Tasks

- [x] **Task 1 — Foundation: full-document pin + skeleton/context specs.**
  Create `spec/odata_duty/oas2/full_document_spec.rb` (and a `full-document` support schema)
  under `RSpec.describe OdataDuty::OAS2`. Build a realistic builder-DSL schema exercising every
  renderer: title + version set; one enum type; one complex type; a full-CRUD entity set
  (resolver defines `collection`, `individual`, `create`, `update`, `delete`, `count`,
  `od_search`, `od_top`, `od_skip`, `od_skiptoken`, `od_after_init`) whose entity has a
  non-nullable property, a nullable property, an enum property, and a `mutability: :computed`
  property; plus a read-only entity set (only `collection` + `individual`) with a different key
  type. Assert **exact equality** of the entire `OAS2.build_json(schema)` output (backbone pin).
  Add targeted specs: `info` empty `{}` when the schema sets no `version`/`title`; a
  no-`context:` invocation renders the document (defaults to `nil`). Remove the 10 non-nested
  `.mutant.yml` entries: `OAS2#initialize`, `OAS2.build_json`, `#add_error_definition`,
  `#add_enum_definitions`, `#add_complex_definitions`, `#register_definition`,
  `#add_request_body_definitions`, `#add_collection_paths`, `#add_individual_paths`,
  `#wrap_context`. Verify: `bundle exec rake` green **and** those 10 subjects survivor-free via
  scoped `mutant run`.
  Excerpt: PRD "External API" representative schema; "Behavior & expected I/O" full-document pin;
  Resolution guide rows "Document skeleton", "Capability gating", "Context plumbing".

- [x] **Task 2 — CollectionPostPath group (9 subjects).**
  Consolidate the create `$oas2` specs (`spec/odata_duty/{entity_set,schema_builder/entity_set}/create/oas2_spec.rb`)
  into the new home, re-anchored to `RSpec.describe OdataDuty::OAS2, '...'`. Pin the exact POST
  operation hash (operationId `Create<Name>`, `produces`, body param `required: true` `$ref`ing
  `<Entity>Create`, responses 200 `Success` / 201 `Created` / `default`), plus the
  `<Entity>Create` definition incl. `required` derivation (non-nullable settable-on-create) and
  its omission when that list is empty. Remove the 9 `OAS2::CollectionPostPath*` entries. Verify
  rake green + those 9 subjects survivor-free.
  Excerpt: PRD "The pinned document contract" (POST bullets), Resolution guide "Collection POST".

- [x] **Task 3 — Individual GET + DELETE groups (3 + 6 subjects).**
  Add/consolidate the GET-individual and DELETE `$oas2` specs into the new home under
  `RSpec.describe OdataDuty::OAS2`. GET: exact operation hash (`GetIndividual<Name>ById`,
  `produces`, 200 `$ref` entity, `default`) with **both** id-type variants (Integer key →
  `type: 'integer'`, else `'string'`). DELETE: exact operation hash (`Delete<Name>`, id param,
  204 `No Content` with no schema, `default`, **no `produces` key**) and both id-type variants.
  Move the existing delete oas2 specs. Remove the 3 `IndividualGetPath*` + 6 `IndividualDeletePath*`
  entries. Verify rake green + those 9 subjects survivor-free.
  Excerpt: PRD "Operations" (id param + produces bullets), Resolution guide "Individual GET" /
  "Individual DELETE".

- [x] **Task 4 — IndividualPatchPath group (10 subjects).**
  Consolidate the update `$oas2` specs into the new home under `RSpec.describe OdataDuty::OAS2`.
  Pin the exact PATCH operation hash (`Update<Name>`, `produces`, id param + body param
  `$ref`ing `<Entity>Update`, 200 `Success` `$ref` entity, `default`) and the `<Entity>Update`
  definition (settable-on-update properties, **never** a `required` key). Remove the 10
  `OAS2::IndividualPatchPath*` entries. Verify rake green + those 10 subjects survivor-free.
  Excerpt: PRD "The pinned document contract" (PATCH bullets), Resolution guide "Individual PATCH".

- [ ] **Task 5 — Consolidation, no-regression sweep, docs.**
  Remove the now-redundant `$oas2` sections from the mixed / duplicate files
  (`entity_set/create|update|delete/oas2_spec.rb`, `schema_builder/entity_set/create|update|delete/oas2_spec.rb`,
  both `computed_oas2_spec.rb`, `collection_scalars_oas2_spec.rb`, the `#oas_2` sections in both
  `search_spec.rb`, `schema_builder_spec.rb`, `collection_spec.rb`, `od_after_init_spec.rb`),
  folding any still-unique coverage into the `OdataDuty::OAS2` home and keeping a small anchor
  under the original describe constant only where a behavior is load-bearing for that subject.
  Confirm `.mutant.yml` has **zero** `OdataDuty::OAS2*` entries left. Run scoped
  `mutant run 'OdataDuty::EntitySet*'` and `'OdataDuty::SchemaBuilder*'` → zero new alive, and a
  final `mutant run 'OdataDuty::OAS2*'` → survivor-free. Optional one-line README note that
  `OAS2.build_json` requires a builder-DSL schema. Bump `spec.version` in the gemspec **iff** any
  `lib/` simplification landed. Verify rake green.
  Excerpt: PRD "Spec anchoring", "Mandatory no-regression verification", Scope, Documentation impact.
