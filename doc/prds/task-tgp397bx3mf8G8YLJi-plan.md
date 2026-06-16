# Build plan — Reflect unimplemented `create` in `$metadata`, `$oas2`, and MCP

PRD: [task-tgp397bx3mf8G8YLJi.md](./task-tgp397bx3mf8G8YLJi.md)

## Context / shared decisions

The feature mirrors the existing `od_search` capability reflection (`supports_search?`).
Detection contract per PRD: a set "supports create" when its resolver/data class responds to
`create` — `resolver_class.method_defined?(:create)` (builder DSL),
`entity_set.method_defined?(:create)` (class DSL). Base classes (`SetResolver`, `EntitySet`) do
**not** define `create`, so `method_defined?` is clean.

`supports_create?` is internal, so it is exercised only through its observable effects on `$oas2`,
`$metadata`, and MCP (public-API-only tests). Tasks are therefore decomposed by output, each adding
the predicate where its consumer needs it.

Established mirror convention (from `search_spec.rb`): the class-DSL spec tree tests `$oas2` and
`$metadata` by constructing a **builder** schema for those sub-sections (OAS2 is only ever rendered
from a builder schema), while `#execute`/`mcp` sections use the class-DSL schema directly. Follow
that convention. The `$metadata` template (`lib/metadata.xml.erb`) is shared by both DSLs, so the
class-DSL `$metadata` test can additionally use the class schema's `metadata_xml` to genuinely
exercise `EntitySet::Metadata#supports_create?`.

## Tasks

- [x] **Task 1 — `$oas2`: gate the `post` collection path on create availability**
  - Task text: Add a `supports_create?` predicate to the builder `SchemaBuilder::EntitySet`
    (`resolver_class.method_defined?(:create)`), mirroring `supports_search?`. In
    `OAS2#add_collection_paths` (`lib/odata_duty/oas2.rb`), emit the `'post' =>
    CollectionPostPath...` entry only when `entity_set.supports_create?`; the `'get'` is unchanged.
    Read-only sets (no `create`) get only `get`; writable sets keep both `get` and `post`. Add
    mirrored specs under `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`
    (both using a builder-constructed schema for the OAS2 assertions, per the search_spec
    convention): a creatable set's path has `post` with `operationId "Create<Set>"`; a read-only
    set's path has no `post`.
  - Likely files: `lib/odata_duty/schema_builder/entity_set.rb`, `lib/odata_duty/oas2.rb`;
    specs `spec/odata_duty/entity_set/create/oas2_spec.rb`,
    `spec/odata_duty/schema_builder/entity_set/create/oas2_spec.rb`.
  - PRD excerpt: "$oas2 emits a post operation on every collection path … even for read-only sets";
    read-only `/People` → only `get`; writable `/Widgets` → `get` + `post`
    (`CreateWidgets`/`ListWidgets`). Scope: gating the OAS2 post path on create availability.
  - Depends on: none (introduces `supports_create?` on builder EntitySet).

- [x] **Task 2 — `$metadata`: `Capabilities.InsertRestrictions` (`Insertable=false`) for read-only sets**
  - Task text: Add `supports_create?` to the class-DSL `OdataDuty::EntitySet::Metadata`
    (`entity_set.method_defined?(:create)`), mirroring its `supports_search?`. In the shared EDMX
    template `lib/metadata.xml.erb`, emit an `Annotation Term="Capabilities.InsertRestrictions"`
    with `<PropertyValue Property="Insertable" Bool="false" />` for each `EntitySet` where
    `!entity_set.supports_create?`; creatable sets get no such annotation (default-insertable).
    Add mirrored specs: class-DSL tree uses the class schema's `metadata_xml`; builder-DSL tree
    uses the builder schema's `metadata_xml`. Assert the annotation is present for a read-only set
    and absent for a creatable set (scope the XML to each `<EntitySet>` block, as search_spec does).
  - Likely files: `lib/odata_duty.rb` (`EntitySet::Metadata#supports_create?`),
    `lib/metadata.xml.erb`; specs `spec/odata_duty/entity_set/create/metadata_spec.rb`,
    `spec/odata_duty/schema_builder/entity_set/create/metadata_spec.rb`.
  - PRD excerpt: read-only `<EntitySet Name="People">` carries `Capabilities.InsertRestrictions` →
    `Insertable="false"`; writable `<EntitySet Name="Widgets" … />` has no annotation. The
    `Org.OData.Capabilities.V1` reference is already declared at the top of the EDMX.
  - Depends on: Task 1 (builder `supports_create?` already present; this adds the class-DSL one and
    the shared template change).

- [x] **Task 3 — MCP: `create_<EntitySet>` tool in `tools/list` and `tools/call`**
  - Task text: Add `supports_create?` to builder `SchemaBuilder::Endpoint` (delegating to
    `entity_set.supports_create?`), mirroring its `supports_search?` delegation. In
    `MCPExecutor#handle_tools_list`, additionally list a `create_<EntitySet>` tool for each endpoint
    whose set `supports_create?` (alongside any `search_` tools): name `"create_#{endpoint.name}"`,
    description `"Create a new #{endpoint.name} record"`, and an `inputSchema` of
    `{ 'type' => 'object', 'properties' => <entity type properties>, ... }` built from the entity
    type's properties (`endpoint.entity_type.properties` + `Property#to_oas2`, mirroring
    `SchemaBuilder::ComplexType#to_oas2`) — the same writable body shape OAS2's post advertises. In
    `handle_tools_call`, dispatch `create_`-prefixed tool names to the create path
    (`Executor.create(url:, context:, query_options: arguments, schema:)`), returning the created
    entity as structured JSON (`Oj.load`), the way `search_` reuses the read path. Read-only sets
    list no `create_` tool, so calling one hits the existing "Unknown tool" error. Add mirrored
    specs under both spec trees (class-DSL tree uses the class schema via `handle_jsonrpc`;
    builder-DSL tree uses the builder schema): `create_<Set>` present for a creatable set and absent
    for a read-only set; a `tools/call` for `create_<Set>` creates and returns the record.
  - Likely files: `lib/odata_duty/schema_builder/endpoint.rb`, `lib/odata_duty/mcp_executor.rb`;
    specs `spec/odata_duty/entity_set/create/mcp_spec.rb`,
    `spec/odata_duty/schema_builder/entity_set/create/mcp_spec.rb`.
  - PRD excerpt: `tools/list` includes `create_Widgets` (`"Create a new Widgets record"`,
    inputSchema object with the writable properties) and omits `create_People`; a `tools/call` for
    `create_Widgets` creates the record and returns the created entity as structured JSON, reusing
    `Schema.create`/`Executor.create`. Both DSLs, mirrored specs.
  - Depends on: Task 1 (builder `supports_create?` on EntitySet), Task 2 (class-DSL
    `supports_create?`). Endpoint delegates to EntitySet; class-DSL `EntitySet::Metadata` is the
    endpoint object for the class schema.

- [x] **Task 4 — Documentation: `doc/using_create.md` + README cross-link**
  - Task text: Add `doc/using_create.md` in the house style (purpose-first, example-driven, ending
    in a "Common Error Cases" section), covering: implementing `create` makes a set writable;
    omitting it makes the set read-only; and how that choice is reflected across `$oas2` (post
    omitted), `$metadata` (`InsertRestrictions Insertable=false`), and MCP (`create_<EntitySet>`
    tool present/absent). Show both the builder-DSL resolver and class-DSL entity-set forms.
    Cross-link the guide from the create-related parts of `README.md`.
  - Likely files: `doc/using_create.md` (new), `README.md`.
  - PRD excerpt: "Documentation impact" section.
  - Depends on: Tasks 1–3 (documents their behavior).

---

## Review follow-up (PR review comments — 2026-06-16)

Four unresolved reviewer comments against the original implementation. Addressed as two tasks.

- [x] **Task R1 — Guard `handle_tools_call` against a nil endpoint**
  - Task text: `handle_tools_call` can call `run_tool` with `endpoint == nil` when a client calls a
    tool like `search_Unknown` (or `search_` with an empty suffix), raising `NoMethodError` on
    `endpoint.url` instead of the intended "Unknown tool" error. Validate the endpoint and its
    capability before dispatching for the `search_` prefix, mirroring the existing `create_` guard
    (`endpoint&.supports_create?`). Add a failing test first (e.g. `tools/call` for `search_Unknown`
    expects an "Unknown tool" error). Mirror the spec in both spec trees.
  - Likely files: `lib/odata_duty/mcp_executor.rb`; specs
    `spec/odata_duty/entity_set/create/mcp_spec.rb`,
    `spec/odata_duty/schema_builder/entity_set/create/mcp_spec.rb` (or a sibling MCP spec).
  - PRD excerpt: "MCP `tools/call` for `create_<EntitySet>` on a read-only set: the tool is not in
    `tools/list`, so calling it raises the existing 'Unknown tool' error." The same must hold for an
    unknown `search_` tool name.
  - Depends on: original Task 3.

- [x] **Task R2 — Correct `doc/using_create.md` examples to match the implementation**
  - Task text: Fix three doc inaccuracies in `doc/using_create.md`: (a) the MCP `tools/list`
    `required` array must include the key `id` (built from all non-nullable properties, and
    `property_ref` is always `nullable: false`) → `["id", "user_name", "emails"]`; (b) the
    `NoImplementationError` message has no leading slash — `create not implemented for People`, since
    it is built from `endpoint.url`; (c) the coercion/validation error bullet must name the classes
    the create path actually raises: `CreateComplexTypeHashWrapper` rescues `InvalidValue` and raises
    `OdataDuty::InvalidType`, and accessing an undefined field on the input raises
    `OdataDuty::NoSuchPropertyError` (unknown body keys are otherwise ignored unless accessed) — drop
    the nonexistent `UnknownPropertyError`/standalone `InvalidValue` framing.
  - Likely files: `doc/using_create.md` (docs only — no code/tests).
  - PRD excerpt: "Common error cases" and the MCP `tools/list` example in the PRD.
  - Depends on: Task R1 (documents corrected behavior).
