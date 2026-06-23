# PRD: Computed (read-only) properties

## Summary
Add a `computed: true` option to the `property` DSL so a gem consumer can mark a property as
server-generated / read-only. Computed properties still appear in GET responses, `$metadata`, and
the entity's OAS2 definition, but are excluded from the create-input contract (OAS2 POST body, MCP
`create_<Set>` tool, and the typed `create` input object). This follows OData's
`Org.OData.Core.V1.Computed` term; the gem documents that it adopts OData Core vocabulary keyword
names where practical.

## Goal / Problem
Today every property is implicitly writable on create. The framework's `create` input wrapper
accepts a value for *any* declared property, the OAS2 `POST` body references the full entity
definition, and the MCP `create_<Set>` tool lists *all* properties (with non-nullable ones marked
`required`). There is no way to express "this value is assigned by the server, not the client" —
e.g. an `id`, `created_at`, or a derived/virtual field. Consumers are forced to document such
fields out-of-band, and tools (PowerBI, PowerAutomate, LLMs via MCP) wrongly prompt for them on
create.

**Expected:** A consumer declares a property `computed: true` and that single declaration removes
it from every create-input contract while keeping it in every read contract.

## What it enables
- As a gem consumer, I can mark `property 'created_at', DateTime, computed: true` so clients see it
  in responses but are never asked to supply it on create.
- As a gem consumer, I get the entity key (`property_ref`) treated as server-assigned **by
  default**, matching common OData practice — no extra flag needed.
- As a gem consumer, I can opt a key back into client-supplied creates with
  `property_ref 'id', String, computed: false`.
- The distinction propagates automatically to `$metadata` (Core.Computed annotation), `$oas2`
  (`readOnly: true`), and MCP (excluded from the create tool input schema) — define once, reflected
  everywhere.

Scope limit: this controls **create** input only (the gem has no update/PATCH today). The term is
forward-compatible with a future update path.

## External API

A new keyword `computed:` (default `false`) on `property`. `property_ref` defaults to
`computed: true`.

### Class DSL (`OdataDuty::EntityType`)
```ruby
class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String                      # computed (read-only) by default
  property 'user_name', String, nullable: false  # writable
  property 'name', String                         # writable
  property 'created_at', DateTime, computed: true # read-only, server-assigned
end
```

### Builder DSL (`OdataDuty::SchemaBuilder`)
```ruby
s.add_entity_type(name: 'Person') do |et|
  et.property_ref 'id', String                       # computed by default
  et.property 'user_name', String, nullable: false
  et.property 'created_at', DateTime, computed: true
end
```

**Contract:** `computed: true` marks a property read-only. It is still rendered by the entity mapper
in `collection`/`individual`/`create` *responses*. It is removed from the *create input* surface:
the OAS2 POST schema, the MCP `create_<Set>` `inputSchema`, and the typed input object. A client
value supplied for a computed property is **silently ignored** — no error — and
`input.<computed_prop>` inside `create` returns `nil` regardless of what the body contained.

## Behavior & expected I/O

**GET (unchanged):** computed properties render normally.
```jsonc
{ "@odata.id": "...People('1')", "id": "1", "user_name": "alice",
  "name": "Alice", "created_at": "2026-06-23T10:00:00Z" }
```

**`$metadata` (EDMX):** a computed property carries the Core annotation; the document gains a `Core`
vocabulary reference.
```xml
<edmx:Reference Uri=".../Org.OData.Core.V1.xml">
  <edmx:Include Namespace="Org.OData.Core.V1" Alias="Core" />
</edmx:Reference>
...
<Property Name="created_at" Nullable="true" Type="Edm.DateTimeOffset">
  <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
<Property Name="id" Nullable="false" Type="Edm.String">
  <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
```

**`$oas2`:** the entity definition marks computed properties `readOnly: true` (Swagger 2.0: may
appear in responses, MUST NOT be sent in requests). The `POST` body keeps referencing the same
`#/definitions/Person`, so the flag alone drives create-input exclusion.
```jsonc
"definitions": {
  "Person": {
    "type": "object",
    "properties": {
      "id":         { "type": "string", "readOnly": true },
      "user_name":  { "type": "string" },
      "name":       { "type": "string", "x-nullable": true },
      "created_at": { "type": "string", "format": "date-time", "readOnly": true, "x-nullable": true }
    }
  }
}
```

**MCP `tools/list` (writable set):** computed properties are absent from `properties` and from
`required`.
```jsonc
{ "name": "create_People", "description": "Create a new People record",
  "inputSchema": {
    "type": "object",
    "properties": {
      "user_name": { "type": "string" },
      "name":      { "type": "string", "x-nullable": true }
    },
    "required": ["user_name"] } }
```
Before this change, `inputSchema.properties` also included `id` and `created_at`, and `required` was
`["id", "user_name"]`.

**Create (POST / MCP `create_People`):** a body of
`{ "id": "999", "user_name": "alice", "created_at": "..." }` ignores `id` and `created_at`;
`input.user_name` is `"alice"`, `input.id` is `nil`.

## Common error cases
- **Computed value supplied on create:** silently dropped — **no** error raised (notably, no
  `InvalidType` even if the supplied value is the wrong type, since the value is never coerced).
- **`computed:` given a non-boolean:** treated truthily like other boolean flags (`nullable:`),
  consistent with existing DSL behavior; no new error.
- All existing create errors are unchanged: wrong-typed *writable* values still raise
  `OdataDuty::InvalidType`; `POST` to a set without `create` still raises
  `OdataDuty::NoImplementationError`.

## Scope
- **In:** class-based DSL and builder DSL `property`/`property_ref`; `$metadata`, `$oas2`, and MCP
  create-tool outputs; the typed `create` input object.
- **Out:** update/PATCH semantics (none exist yet); per-operation granularity beyond create
  (`Core.Immutable`, `Core.Permissions`); `$select`/`$filter` behavior (computed properties remain
  fully selectable and filterable).

## Documentation impact
New guide `doc/using_computed.md`, modeled on `doc/using_create.md` (purpose → both DSLs → reflected
contracts → common errors), linked from README's "Further Documentation". It should also state the
broader convention: the gem adopts OData Core vocabulary keyword names where practical.

## Open questions
- Should `input.<computed_prop>` raise instead of returning `nil`? Draft assumes `nil` so existing
  `create` bodies that reference the key won't break.