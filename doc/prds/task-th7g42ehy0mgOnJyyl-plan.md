# Build plan: `delete` support

PRD: [task-th7g42ehy0mgOnJyyl.md](./task-th7g42ehy0mgOnJyyl.md)

Add a third record-level write operation, `delete`, mirroring `create`/`update` exactly:
inferred by method presence on the data class (class DSL) / resolver (builder DSL); reflected
across `$oas2` (a `delete` op on the individual path), `$metadata` (a `DeleteRestrictions`
annotation when absent), and MCP (a `delete_<Set>` tool); plus Rails generator scaffolding and
docs.

Both DSLs and both spec trees (`spec/odata_duty/entity_set/**`, `spec/odata_duty/schema_builder/**`)
must stay in sync. TDD per `.claude/skills/test-driven-development/SKILL.md`. Green gate is
`bundle exec rake` (RSpec + RuboCop). One commit per task.

## Tasks

### - [x] Task 1 — Core `delete` operation + `schema.delete` entry point (both DSLs)

Add the `delete(id)` hook, inferred by method presence, and a public entry point
`schema.delete(url, context:, query_options:)` for the OData `DELETE` verb against an individual
URL. `delete(id)` receives the coerced key (same value `individual`/`update` receive) and takes no
input body. Truthy return → success (no entity payload); falsey → `ResourceNotFoundError`.

Likely files:
- Class DSL: `lib/odata_duty.rb` (`Schema.delete`, `EntitySet::Metadata#delete`),
  `lib/odata_duty/executor.rb` (`Executor.delete` class + instance method).
- Builder DSL: `lib/odata_duty/schema_builder.rb` (`#delete`),
  `lib/odata_duty/schema_builder/endpoint.rb` (`#delete`).
- Specs: `spec/odata_duty/entity_set/delete/with_scalars_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/delete/with_scalars_spec.rb`.

PRD excerpt (External API + Behavior + Common error cases):
- `delete(id)` inferred from method presence, identical to `create`/`update`. Truthy on success;
  falsey → `ResourceNotFoundError` (`No such entity <id>`).
- New public entry point `schema.delete(url, context:, query_options:)`, mirroring
  `schema.execute`/`create`/`update`. The individual URL (`People('1')`) carries the key; no body.
- `schema.delete` returns no entity payload — the framework validates the key, dispatches to
  `delete(id)`, confirms a truthy result. On success the controller emits `204 No Content`.
- `DELETE` to a set without `delete` → `NoImplementationError` (`delete not implemented for <url>`).
- `DELETE` for a missing key (falsey return) → `ResourceNotFoundError` (`No such entity <id>`).
- Invalid key in the URL → `InvalidPropertyReferenceValue` (`Invalid individual id : ...`).

Dependencies: none (foundational).

### - [x] Task 2 — `$metadata` `DeleteRestrictions` annotation + `supports_delete?` predicates

Add `supports_delete?` predicates (class DSL `EntitySet::Metadata`, builder
`SchemaBuilder::EntitySet` + delegating `Endpoint`) detecting the `delete` method, and emit a
`DeleteRestrictions` annotation in `$metadata` when the set is **not** deletable, parallel to the
existing `InsertRestrictions`/`UpdateRestrictions` blocks. A deletable set gets no annotation.

Likely files: `lib/metadata.xml.erb`, `lib/odata_duty.rb`,
`lib/odata_duty/schema_builder/entity_set.rb`, `lib/odata_duty/schema_builder/endpoint.rb`.
Specs: `spec/odata_duty/entity_set/delete/metadata_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/delete/metadata_spec.rb`.

PRD excerpt (`$metadata`):
```xml
<EntitySet Name="Countries" EntityType="MySpace.Country">
    <Annotation Term="Capabilities.DeleteRestrictions">
        <Record>
            <PropertyValue Property="Deletable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```
A fully writable set (create + update + delete) carries none of the three restriction annotations.

Dependencies: Task 1.

### - [x] Task 3 — `$oas2` `delete` operation on the individual path

A deletable set's individual path gains a `delete` alongside `get` (and `patch` if updatable).
`operationId` is `Delete<Set>`; its only parameter is the `id` path parameter (no body); success
response is `204 No Content` with no schema, plus the standard `default` Error. Non-deletable sets
omit `delete` entirely.

Likely files: `lib/odata_duty/oas2.rb` (`add_individual_paths`),
`lib/odata_duty/oas2/individual_delete_path.rb` (new, mirroring `individual_patch_path.rb`).
Specs: `spec/odata_duty/entity_set/delete/oas2_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/delete/oas2_spec.rb`.

PRD excerpt (`$oas2`):
```jsonc
"delete": {
  "operationId": "DeletePeople",
  "parameters": [ { "name": "id", "in": "path", "required": true, "type": "string" } ],
  "responses": {
    "204": { "description": "No Content" },
    "default": { "description": "Unexpected error", "schema": { "$ref": "#/definitions/Error" } }
  }
}
```

Dependencies: Tasks 1, 2 (`supports_delete?`).

### - [x] Task 4 — MCP `delete_<Set>` tool

`tools/list` includes a `delete_<Set>` tool for each deletable set: `name` `delete_<Set>`,
`description` `"Delete an existing <Set> record"`, `inputSchema` an object whose `properties`
contain **only the key property** and whose `required` is **only the key** (key defaults to
computed → `"readOnly": true`). `tools/call` deletes the record reusing the REST `DELETE` path and
returns a simple acknowledgement (no entity payload, `isError` false). Non-deletable sets advertise
no such tool (calling it → `Unknown tool` error).

Likely files: `lib/odata_duty/mcp_server_builder.rb` (`register_delete_tool` + dispatch in
`register_endpoint_tools`), `lib/odata_duty/mcp_input_schemas.rb` (`delete_input_schema`).
Specs: `spec/odata_duty/entity_set/delete/mcp_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/delete/mcp_spec.rb`.

PRD excerpt (MCP):
```jsonc
{
  "name": "delete_People",
  "description": "Delete an existing People record",
  "inputSchema": {
    "type": "object",
    "properties": { "id": { "type": "string", "readOnly": true } },
    "required": ["id"]
  }
}
```

Dependencies: Tasks 1, 2 (`supports_delete?`).

### - [x] Task 5 — Rails `install` generator: `destroy` action + `delete` route

The generated controller gains a `destroy` action calling `schema.delete(...)` then
`head :no_content`; `route_contents` adds `delete '*url' => '<controller>#destroy'` to the
generated `scope '/api'` block. Scope strictly to `delete` (do not also add the missing `patch`).

Likely files: `lib/generators/odata_duty/install/install_generator.rb` (`route_contents`),
`lib/generators/odata_duty/install/templates/controller.rb.tt`.
Specs: `spec/generators/install_generator_spec.rb`.

PRD excerpt:
```ruby
def destroy
  schema.delete(params[:url], context: self, query_options: query_options)
  head :no_content
end
```
```ruby
delete '*url' => 'api#destroy'
```

Dependencies: Task 1.

### - [x] Task 6 — Rails `entity_set` generator: scaffold `delete(id)` + spec example

`resolver.rb.erb` (builder) and `entity_set.rb.erb` (class) gain an optional, ready-to-edit
`delete(id)` method alongside `create`. The generated specs gain a `#delete` example covering the
success and not-found (`ResourceNotFoundError`) paths.

Likely files under `lib/generators/odata_duty/entity_set/templates/`: `resolver.rb.erb`,
`entity_set.rb.erb`, `resolver_spec.rb.erb`, `entity_set_spec.rb.erb`.
Specs: `spec/generators/entity_set_generator_spec.rb` (assert generated output + Ruby syntax).

PRD excerpt (resolver template):
```ruby
# Optional: Implement delete method to support DELETE operations
def delete(id)
  # Find and remove the entity by id; return truthy on success, falsey if not found
  <%= file_name %> = @<%= file_name.pluralize %>.find { |item| item.<%= attributes.first.name %> == id }
  return nil unless <%= file_name %>

  @<%= file_name.pluralize %>.delete(<%= file_name %>)
  <%= file_name %>
end
```

Dependencies: Task 1.

### - [ ] Task 7 — Documentation

Extend `doc/using_create_and_update.md` to cover `delete` as the third write operation (retitle to
cover create / update / delete), preserving its purpose-first, example-driven, "Common Error Cases"
structure. Update `doc/entity_set_generator.md` to document the scaffolded `delete(id)` method and
the generated `destroy` action / `delete` route. Update `README.md` cross-references (the
"Implementing `create` makes a set insertable…" sentence and the Further Documentation list).

Likely files: `doc/using_create_and_update.md` (possibly renamed), `doc/entity_set_generator.md`,
`README.md`, and any internal links to the renamed guide.

Dependencies: Tasks 1–6 (documents the shipped behavior).
