# Build plan: Update support (`update` hook / OData `PATCH`)

PRD: [task-th38zacwjiEpEAHdxt.md](./task-th38zacwjiEpEAHdxt.md)

Implements an `update(id, input)` hook that mirrors `create(input)` across both DSLs, exposing
OData `PATCH`, a `$oas2` `patch` operation, an `UpdateRestrictions` `$metadata` annotation for
non-updatable sets, and an `update_<Set>` MCP tool. Each task lands as its own commit after
spec-compliance and code-quality review pass and `bundle exec rake` is green.

## Reference points in the codebase (how `create` is wired — `update` mirrors it)

- `Executor` dispatch: `lib/odata_duty/executor.rb` — `self.create`, instance `#create`,
  `extract_value_from_brackets`, `#individual` (id coercion path).
- Class DSL: `lib/odata_duty.rb` — `Schema.create` (262), `EntitySet::Metadata#create` (96),
  `#supports_create?` (113), `converted_id` (120).
- Builder DSL: `lib/odata_duty/schema_builder.rb` — `#create` (89); `schema_builder/endpoint.rb`
  — `#create`, `#supports_create?`, `converted_id`; `schema_builder/entity_set.rb` —
  `#supports_create?`.
- Input object: `lib/odata_duty/create_complex_type_hash_wrapper.rb`.
- `$oas2`: `lib/odata_duty/oas2.rb` (`add_collection_paths`/`add_individual_paths`),
  `oas2/collection_post_path.rb`, `oas2/individual_get_path.rb`.
- `$metadata`: `lib/metadata.xml.erb` (InsertRestrictions block ~78).
- MCP: `lib/odata_duty/mcp_server_builder.rb` (`register_create_tool`, `create_input_schema`,
  `define_tool`, `run_tool`).

Note: the key property (`property_ref`) defaults to `computed: true`, so it is excluded from
`create_input_schema`; the `update` MCP tool must add it back and mark it the sole `required`.
The `$oas2` individual path key encoding (`/Set({id})`) is reused as-is; `update` only adds a
`patch` to that existing path object.

## Tasks

- [x] **Task 1 — Core REST `PATCH` end-to-end (both DSLs) + `supports_update?` predicate**

  Add the `update(id, input)` hook and route `PATCH` through it, mirroring `create`.
  - `Executor.update` + instance `#update`: extract the id from the URL brackets (like
    `#individual`), call `endpoint.update(id, context:)`, merge the individual `@odata.context`
    anchor (`#{endpoint.name}/$entity`), and rescue `NoMethodError` → `NoImplementationError,
    "update not implemented for #{endpoint.url}"`.
  - Class DSL: `Schema.update(url, context:, query_options:)` in `lib/odata_duty.rb`;
    `EntitySet::Metadata#update(id, context:)` (coerce id via `converted_id`, build
    `CreateComplexTypeHashWrapper` from `context.query_options`, call
    `entity_set.new(context:).update(id, wrapper)`, raise `ResourceNotFoundError` on a falsey
    result, map result via the entity-type mapper); `EntitySet::Metadata#supports_update?` →
    `entity_set.method_defined?(:update)`.
  - Builder DSL: `SchemaBuilder#update(...)` in `schema_builder.rb`;
    `SchemaBuilder::Endpoint#update(id, context:)` (mirror); `Endpoint#supports_update?` and
    `SchemaBuilder::EntitySet#supports_update?` → `resolver_class.method_defined?(:update)`.
  - Error cases: `NoImplementationError` (no `update`), `ResourceNotFoundError` (falsey result),
    `InvalidPropertyReferenceValue` (bad key), `InvalidType` (bad body value),
    `NoSuchPropertyError` (reading an undefined property) — all identical to `create`/`individual`.

  Defining PRD excerpt: External API → "The `update` hook contract", "Invoking it (Rails
  controller wiring)" (`schema.update(url, context:, query_options:)`); Behavior → "REST `PATCH`"
  request/response JSON; all of "Common error cases".

  Likely files: `lib/odata_duty/executor.rb`, `lib/odata_duty.rb`,
  `lib/odata_duty/schema_builder.rb`, `lib/odata_duty/schema_builder/endpoint.rb`,
  `lib/odata_duty/schema_builder/entity_set.rb`. Specs:
  `spec/odata_duty/entity_set/update/*_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/update/*_spec.rb` (happy path with partial-merge nil
  reads + every error case).

  Dependencies: none. Establishes `supports_update?` used by Tasks 2–4.

- [x] **Task 2 — `$metadata` `UpdateRestrictions` annotation (both DSLs)**

  Emit a `Capabilities.UpdateRestrictions` / `Updatable=false` annotation for sets **without**
  `update`, paralleling the existing `InsertRestrictions` block; updatable sets get no annotation.
  A set that is neither insertable nor updatable carries both.

  Defining PRD excerpt: Behavior → "`$metadata` (EDMX)" XML block.

  Likely files: `lib/metadata.xml.erb`. Specs:
  `spec/odata_duty/entity_set/update/metadata_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/update/metadata_spec.rb`.

  Dependencies: Task 1 (`supports_update?`).

- [ ] **Task 3 — `$oas2` `patch` on the individual path (both DSLs)**

  Add a `patch` to an updatable set's individual path object alongside `get`. `operationId`
  `Update<Set>`; parameters = the `id` path param (as `get` uses) **plus** a required `body` param
  whose `schema` `$ref`s the entity definition; responses `200` (Success) + `default` (Error),
  both schema-`$ref`ing the entity. Omit `patch` when the set has no `update`.

  Defining PRD excerpt: Behavior → "`$oas2`" JSON block.

  Likely files: `lib/odata_duty/oas2.rb` (`add_individual_paths`), new
  `lib/odata_duty/oas2/individual_patch_path.rb` (require it where the other oas2 paths are
  required). Specs: `spec/odata_duty/entity_set/update/oas2_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/update/oas2_spec.rb`.

  Dependencies: Task 1.

- [ ] **Task 4 — MCP `update_<Set>` tool (both DSLs)**

  Register an `update_<Set>` tool for each updatable set, mirroring `create_<Set>`. `name`
  `update_<Set>`; `description` `"Update an existing <Set> record"`; `inputSchema` properties =
  create's writable properties **plus the key property** (which is otherwise computed/excluded),
  `required` = `[key]` only. `tools/call` builds the individual URL from the `id` argument and
  routes through `Executor.update`, returning the updated entity. Non-updatable sets advertise no
  tool (calling one → "Unknown tool" error).

  Defining PRD excerpt: Behavior → "MCP" `tools/list` + `tools/call` JSON blocks; Common error
  cases → "MCP `update_<Set>` for a non-updatable set".

  Likely files: `lib/odata_duty/mcp_server_builder.rb`. Specs:
  `spec/odata_duty/entity_set/update/mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/update/mcp_spec.rb`.

  Dependencies: Task 1.

- [ ] **Task 5 — Documentation: fold `create` + `update` into a write-operations guide**

  Evolve `doc/using_create.md` into a combined write-operations guide (Overview → both DSLs → How
  it works → `$oas2`/`$metadata`/MCP reflection → Common Error Cases), presenting `update`
  alongside `create`. Update the README *Further Documentation* link to the combined guide.

  Defining PRD excerpt: "Documentation impact".

  Dependencies: Tasks 1–4 (documents shipped behavior).
