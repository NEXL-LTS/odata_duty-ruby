# Build plan: Per-operation `$oas2` request-body schemas

PRD: [`property-mutability-oas2-bodies.md`](property-mutability-oas2-bodies.md)

## Context

`$oas2` generation lives entirely in `lib/odata_duty/oas2.rb` + `lib/odata_duty/oas2/*`
and operates on a `SchemaBuilder::Schema` (DSL-agnostic). Both spec trees
(`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`) exercise it via
`OdataDuty::OAS2.build_json(schema, context:)` with builder-constructed schemas — the
existing convention. Properties already expose `settable_on_create?` (`:read_write` +
`:immutable`) and `settable_on_update?` (`:read_write` + `:non_insertable`) from Parts A/B,
and `to_oas2` already emits `readOnly: true` for `:computed`.

Existing specs that assert the OLD shared-ref bodies and must be revised as part of the
relevant task:
- `spec/odata_duty/{entity_set,schema_builder/entity_set}/computed_oas2_spec.rb` — "keeps the
  post body referencing the shared entity definition" (Task 1).
- `spec/odata_duty/{entity_set,schema_builder/entity_set}/update/oas2_spec.rb` — patch body
  `$ref` to shared entity (Task 2).

## Tasks

### Task 1 — Emit `<Entity>Create` definition; point `POST` body at it

- [x] **Title:** Per-operation Create request body in `$oas2`

**Task text:** In `lib/odata_duty/oas2.rb` + `lib/odata_duty/oas2/collection_post_path.rb`,
emit a new `<Entity>Create` definition for every create-able entity set and make the `post`
operation's `body` parameter reference `#/definitions/<Entity>Create` instead of the shared
`#/definitions/<Entity>`. The `200`/`201` responses keep referencing the full
`#/definitions/<Entity>`. `<Entity>Create` contains only properties settable on create
(`property.settable_on_create?` — i.e. `:read_write` + `:immutable`; `:computed` and
`:non_insertable` omitted), using the same `property.to_oas2` rendering as the response
definition. Its `required` array lists the non-nullable create-settable properties (mirroring
`McpInputSchemas.create_input_schema`); omit the `required` key when empty. Emit
`<Entity>Create` for **every** create-able set, even one with no constrained properties (body
then equals the writable set). Do **not** emit `x-ms-mutability`. Update the existing specs
that assert the old shared post-body ref. Add specs in **both** spec trees covering: the
`<Entity>Create` definition's properties + `required`, the post body `$ref` pointing at it,
the responses still pointing at `<Entity>`, and the uniform-emission case (no constrained
props).

**Defining PRD excerpt:** `<Entity>Create` — the `POST` request body. Only properties
settable on create (`:read_write` + `:immutable`); `:computed` and `:non_insertable` omitted.
`OrderCreate` example with `"required": ["account_number"]`. The `post` operation's `body`
parameter references `#/definitions/OrderCreate`; responds with `#/definitions/Order`
(`200`/`201`). Emitted for every create-able set even with no constrained properties.

**Likely files:** `lib/odata_duty/oas2.rb`, `lib/odata_duty/oas2/collection_post_path.rb`;
specs `spec/odata_duty/entity_set/create/oas2_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/create/oas2_spec.rb`,
`spec/odata_duty/{entity_set,schema_builder/entity_set}/computed_oas2_spec.rb`.

**Depends on:** none.

### Task 2 — Emit `<Entity>Update` definition; point `PATCH` body at it

- [x] **Title:** Per-operation Update request body in `$oas2`

**Task text:** In `lib/odata_duty/oas2.rb` + `lib/odata_duty/oas2/individual_patch_path.rb`,
emit a new `<Entity>Update` definition for every update-able entity set and make the `patch`
operation's `body` parameter reference `#/definitions/<Entity>Update` instead of the shared
`#/definitions/<Entity>`. The `id` path parameter and the `200` response are unchanged (`200`
still references `#/definitions/<Entity>`). `<Entity>Update` contains only properties settable
on update (`property.settable_on_update?` — i.e. `:read_write` + `:non_insertable`;
`:computed` and `:immutable` omitted; the key travels in the path, not the body), using the
same `property.to_oas2` rendering. PATCH is partial-merge, so emit **no** `required` key
(matching the PRD's `OrderUpdate` example). Emit `<Entity>Update` for **every** update-able
set, even one with no constrained properties. Do **not** emit `x-ms-mutability`. Update the
existing specs that assert the old shared patch-body ref. Add specs in **both** spec trees
covering: the `<Entity>Update` definition's properties, the patch body `$ref` pointing at it,
the `200` response still pointing at `<Entity>`, and the uniform-emission case.

**Defining PRD excerpt:** `<Entity>Update` — the `PATCH` request body. Only properties
settable on update (`:read_write` + `:non_insertable`); `:computed` and `:immutable` omitted.
(The key travels in the path, not the body.) `OrderUpdate` example has no `required`. The
`patch` operation's body references `#/definitions/OrderUpdate`; responds with
`#/definitions/Order` (`200`). Emitted for every update-able set even with no constrained
properties.

**Likely files:** `lib/odata_duty/oas2.rb`, `lib/odata_duty/oas2/individual_patch_path.rb`;
specs `spec/odata_duty/entity_set/update/oas2_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/update/oas2_spec.rb`, plus a constrained-properties
spec in both trees.

**Depends on:** Task 1 (shared `add_request_body_definitions` plumbing in `oas2.rb`).

### Task 3 — Documentation + Features index

- [ ] **Title:** Document per-operation `$oas2` bodies

**Task text:** Update `doc/using_mutability.md`: replace the "`$oas2` — not yet
operation-aware (interim gap)" section (and the "`$oas2` is unchanged"/"addressed in a
follow-up" note in the summary) with a `$oas2` section describing the three definitions
(`<Entity>`, `<Entity>Create`, `<Entity>Update`) and the per-operation body mapping (post →
Create, patch → Update, responses → `<Entity>`, `readOnly: true` on `:computed` in the
response, no `x-ms-mutability`). Update `doc/using_create_update_and_delete.md`: revise the
`$oas2` examples so the `post` body references `#/definitions/<Entity>Create` and the `patch`
body references `#/definitions/<Entity>Update` (responses unchanged), including for sets with
no constrained properties; adjust surrounding prose accordingly. Keep `CLAUDE.md`'s `## Features`
"Property mutability" line current (it already points at `doc/using_mutability.md` and now
covers `$oas2`).

**Defining PRD excerpt:** Documentation impact — update `doc/using_mutability.md` with the
`$oas2` section and remove "`$oas2` deferred" notes; update
`doc/using_create_update_and_delete.md`'s `$oas2` examples to reference `<Entity>Create` /
`<Entity>Update`, including for sets with no constrained properties.

**Likely files:** `doc/using_mutability.md`, `doc/using_create_update_and_delete.md`,
`CLAUDE.md`.

**Depends on:** Tasks 1 & 2.
