# Build plan: Computed (read-only) properties

PRD: [task-th2tnp4qjxbGEoiNs2.md](./task-th2tnp4qjxbGEoiNs2.md)

Adds a `computed: true` option to the `property` DSL marking a property as server-generated /
read-only. Computed properties stay in every *read* contract (GET, `$metadata`, OAS2 entity
definition) but are removed from every *create-input* contract (typed `create` input object, MCP
`create_<Set>` tool, OAS2 `readOnly`). `property_ref` defaults to `computed: true`.

## Key ripple (every implementer must know)

`property_ref` now defaults to `computed: true`. That means **every existing entity key** becomes
read-only: `input.id` returns `nil` on create, the key gains a `Core.Computed` annotation in
`$metadata`, `readOnly: true` in OAS2, and is excluded from the MCP create tool. **Many existing
specs across both `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**` will need
updated expectations.** Where an existing test genuinely relies on a *client-supplied* key, opt it
back in with `property_ref 'id', String, computed: false` (this also exercises the opt-out). Each
task must finish on a fully green `bundle exec rake`.

Task order is chosen so each task's output change owns its own spec ripple and no task leaves a
transient breakage (notably MCP exclusion lands before the OAS2 `readOnly` change, since MCP's
input schema consumes `property.to_oas2`).

## Tasks

- [x] **Task 1 — DSL `computed:` flag + create-input exclusion.**
  Add a `computed:` keyword (default `false`) to property definition in both DSLs and store it on
  the shared `Property` representation with a `computed?` predicate. Make `property_ref` default to
  `computed: true` (overridable via `computed: false`) in both DSLs. In the create-input wrapper,
  a computed property is silently ignored: `input.<computed_prop>` returns `nil` regardless of the
  body — no coercion, no `InvalidType`, no error. `respond_to?` for the property stays `true`.
  - Files: `lib/odata_duty/property.rb`, `lib/odata_duty/property/single_prop.rb`,
    `lib/odata_duty/entity_type.rb`, `lib/odata_duty/complex_type.rb`,
    `lib/odata_duty/schema_builder/entity_type.rb`, `lib/odata_duty/schema_builder/complex_type.rb`,
    `lib/odata_duty/create_complex_type_hash_wrapper.rb`.
  - Specs (both trees): `spec/odata_duty/entity_set/create/with_scalars_spec.rb`,
    `.../create/with_complex_spec.rb`, and schema_builder equivalents; update any create spec that
    relied on a client-supplied key.
  - PRD excerpt: "`computed: true` marks a property read-only … removed from the *create input*
    surface … A client value supplied for a computed property is **silently ignored** — no error —
    and `input.<computed_prop>` inside `create` returns `nil`." `property_ref` defaults
    `computed: true`; `property_ref 'id', String, computed: false` opts back in.
  - Depends on: none.

- [ ] **Task 2 — MCP `create_<Set>` tool excludes computed properties.**
  In `create_input_schema`, exclude computed properties from both `properties` and `required`.
  - Files: `lib/odata_duty/mcp_server_builder.rb`.
  - Specs (both trees): `spec/odata_duty/entity_set/create/mcp_spec.rb`, schema_builder equivalent.
  - PRD excerpt: MCP `tools/list` — `inputSchema.properties` omits `id`/`created_at`; `required` is
    `["user_name"]` (was `["id", "user_name"]`). Computed properties absent from `properties` and
    `required`.
  - Depends on: Task 1.

- [ ] **Task 3 — `$metadata` Core.Computed annotation + vocabulary reference.**
  Render `<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />` inside each computed
  `<Property>` (entity and complex), and add the `edmx:Reference` for the
  `Org.OData.Core.V1` vocabulary (Alias `Core`), mirroring the existing Capabilities reference.
  - Files: `lib/metadata.xml.erb` (+ a `computed?` accessor on the metadata-side property if needed).
  - Specs (both trees): `spec/odata_duty/entity_set/create/metadata_spec.rb`, schema_builder
    equivalent, plus any metadata spec asserting key/property XML.
  - PRD excerpt: the `edmx:Reference` for `Org.OData.Core.V1.xml` with `Include Namespace=
    "Org.OData.Core.V1" Alias="Core"`, and `<Annotation Term="Org.OData.Core.V1.Computed"
    Bool="true" />` on `created_at` and on the `id` key property.
  - Depends on: Task 1.

- [ ] **Task 4 — `$oas2` `readOnly: true` on computed properties.**
  Add `'readOnly' => true` to a computed property's OAS2 representation so the shared entity
  definition (used by GET responses and the POST `$ref`) marks it read-only. POST body keeps
  referencing `#/definitions/<Entity>`.
  - Files: `lib/odata_duty/property/single_prop.rb` (`to_oas2`).
  - Specs (both trees): `spec/odata_duty/entity_set/create/oas2_spec.rb`, schema_builder
    equivalent, plus any OAS2 spec asserting entity definitions.
  - PRD excerpt: definitions show `"id": { "type": "string", "readOnly": true }` and
    `"created_at": { "type": "string", "format": "date-time", "readOnly": true, "x-nullable": true }`.
  - Depends on: Tasks 1–2 (MCP exclusion must land first so `to_oas2` readOnly does not leak into
    the MCP create input schema).

- [ ] **Task 5 — Documentation.**
  New guide `doc/using_computed.md` modeled on `doc/using_create.md` (purpose → both DSLs →
  reflected contracts: GET, `$metadata`, `$oas2`, MCP → common errors), linked from the README's
  "Further Documentation". State the broader convention: the gem adopts OData Core vocabulary
  keyword names where practical.
  - Files: `doc/using_computed.md`, `README.md`.
  - PRD excerpt: "New guide `doc/using_computed.md`, modeled on `doc/using_create.md` … linked from
    README's 'Further Documentation'. It should also state the broader convention: the gem adopts
    OData Core vocabulary keyword names where practical."
  - Depends on: Tasks 1–4.
