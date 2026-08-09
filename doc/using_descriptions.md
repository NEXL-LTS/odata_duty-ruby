# Using `description` with OdataDuty

A **description** is author-supplied prose attached to a schema element — a schema, entity type,
complex type, enum type, enum member, property, or entity set. OdataDuty renders it into every
consumer-facing contract that has a slot for it: `$metadata` (as `Org.OData.Core.V1.Description`),
`$oas2`, and the MCP tool/server metadata that an LLM agent reads. One `description:` declaration
propagates everywhere it applies, with no per-format duplication.

## Overview

- **Purpose:** document your domain once — what a `Person` record represents, what `name` means,
  what the `People` set contains — instead of leaving every generated contract unannotated.
- **Declaration:** `description:` is a keyword everywhere except type-level and entity-set
  declarations in the class DSL, and the schema in both DSLs — those use a macro/accessor
  (matching the existing `namespace`/`title`/`version` style).
- **Always optional:** omitting `description:` leaves `$oas2` and MCP output byte-identical to
  not having the feature at all, and `$metadata` semantically unchanged — no `Core.Description`
  annotation is emitted (the template's own whitespace conventions mean the raw XML text isn't
  byte-for-byte identical, but no element or attribute differs). `description: nil` is treated
  exactly the same as omitting it.
- **Convention:** the name mirrors the OData Core vocabulary term `Org.OData.Core.V1.Description`,
  following the same convention as `computed:` (`Core.Computed`) and `mutability: :immutable`
  (`Core.Immutable`) — see [`doc/using_mutability.md`](using_mutability.md).
- **Scope:** this is the OData `Core.Description` (short form) only; there is no `long_description:`.

## Declaring descriptions

Both DSLs accept `description:` on every element. The class DSL uses a `description` class macro
for types/schema/entity-set (readable back with no argument, like `title`/`version`); properties
and enum members take `description:` as a keyword. The builder DSL takes `description:` as a
keyword on every `add_*` call and on `property`/`property_ref`/`member`; the schema uses a
`description=` accessor, matching `title`/`version`.

### Class DSL

```ruby
class GenderEnum < OdataDuty::EnumType
  description 'Gender as recorded at registration'
  member 'Male',   description: 'Recorded as male'
  member 'Female', description: 'Recorded as female'
end

class AddressComplex < OdataDuty::ComplexType
  description 'A postal address'
  property 'street', String, description: 'Street line, including house number'
end

class PersonEntity < OdataDuty::EntityType
  description 'People present at the event'
  property_ref 'id', String, description: 'Server-assigned identifier'
  property 'user_name', String, nullable: false, description: 'Unique login handle'
  property 'name', String, description: 'First name or full name'
  property 'gender', GenderEnum
  property 'address', AddressComplex
end

class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity
  description 'Attendees checked in at the front desk'

  def collection = @records
  def individual(id) = @records.find { |r| r.id == id }
end

class MySchema < OdataDuty::Schema
  namespace 'Sample'
  title 'Sample Service'
  version '1.0'
  description 'Directory of people attending the annual conference'
  entity_sets [PeopleSet]
end
```

Like the other class macros, `description` is a reader when called with no argument:
`PersonEntity.description # => "People present at the event"`.

### Builder DSL

```ruby
schema = OdataDuty::SchemaBuilder.build(namespace: 'Sample', host: 'example.org',
                                        scheme: 'https', base_path: '/api') do |s|
  s.title = 'Sample Service'
  s.version = '1.0'
  s.description = 'Directory of people attending the annual conference'

  gender = s.add_enum_type(name: 'Gender',
                           description: 'Gender as recorded at registration') do |e|
    e.member 'Male',   description: 'Recorded as male'
    e.member 'Female', description: 'Recorded as female'
  end

  address = s.add_complex_type(name: 'Address', description: 'A postal address') do |c|
    c.property 'street', String, description: 'Street line, including house number'
  end

  person = s.add_entity_type(name: 'Person',
                             description: 'People present at the event') do |et|
    et.property_ref 'id', String, description: 'Server-assigned identifier'
    et.property 'user_name', String, nullable: false, description: 'Unique login handle'
    et.property 'name', String, description: 'First name or full name'
    et.property 'gender', gender
    et.property 'address', address
  end

  s.add_entity_set(entity_type: person, resolver: 'PeopleResolver', name: 'People',
                   description: 'Attendees checked in at the front desk')
end
```

## Where each description lands

| Declared on | `$metadata` (EDMX) | `$oas2` | MCP |
| --- | --- | --- | --- |
| Schema | `Org.OData.Core.V1.Description` annotation on `<Schema>` | `info.description` | `instructions` in the `initialize` result |
| Entity type | `Org.OData.Core.V1.Description` on `<EntityType>` | `definitions.<Type>.description` | — |
| Complex type | `Org.OData.Core.V1.Description` on `<ComplexType>` | `definitions.<Type>.description` | — |
| Enum type | `Org.OData.Core.V1.Description` on `<EnumType>` | `definitions.<Type>.description` | — |
| Enum member | `Org.OData.Core.V1.Description` on `<Member>` | — | — |
| Property | `Org.OData.Core.V1.Description` on `<Property>` | `definitions.<Type>.properties.<name>.description` | `inputSchema.properties.<name>.description` on every tool exposing that property |
| Entity set | `Org.OData.Core.V1.Description` on `<EntitySet>` | operation `summary` + `description` | appended to each tool's `description` |

Three cells are intentionally empty — see *Common errors / edge cases* below for why.

The OData service document (`index_hash`) is unchanged: its entries stay `{name, kind, url}`.
OData's service-document `title` is a display name, not a description, so it is never populated
from `description:`.

## Reflected in the generated contracts

### Read and write responses — unchanged

`description:` is pure metadata. Collection JSON, individual JSON, `/$count`, and the
create/update/delete responses are byte-identical whether or not descriptions are declared, and no
description ever appears in a data payload.

### `$metadata` (EDMX)

Every described type, member, property, and entity set gets an `Org.OData.Core.V1.Description`
annotation as its first child (before `<Key>`/`<Member>`/other properties). The schema-level
annotation is the one exception — it's placed after the existing `Version`/`Title` annotations,
not first. All of them use the vocabulary already referenced at the top of the document (aliased
`Core`):

```xml
<Schema Namespace="Sample" xmlns="http://docs.oasis-open.org/odata/ns/edm">
    <Annotation Term="Sample.Version" String="1.0" />
    <Annotation Term="Sample.Title" String="Sample Service" />
    <Annotation Term="Org.OData.Core.V1.Description" String="Directory of people attending the annual conference" />
    <EnumType Name="Gender">
        <Annotation Term="Org.OData.Core.V1.Description" String="Gender as recorded at registration" />
        <Member Name="Male">
            <Annotation Term="Org.OData.Core.V1.Description" String="Recorded as male" />
        </Member>
        <Member Name="Female">
            <Annotation Term="Org.OData.Core.V1.Description" String="Recorded as female" />
        </Member>
    </EnumType>
    <EntityType Name="Person">
        <Annotation Term="Org.OData.Core.V1.Description" String="People present at the event" />
        <Key><PropertyRef Name="id" /></Key>
        <Property Name="user_name" Nullable="false" Type="Edm.String">
            <Annotation Term="Org.OData.Core.V1.Description" String="Unique login handle" />
        </Property>
        <Property Name="name" Nullable="true" Type="Edm.String">
            <Annotation Term="Org.OData.Core.V1.Description" String="First name or full name" />
        </Property>
    </EntityType>
    <EntityContainer Name="Container">
        <EntitySet Name="People" EntityType="Sample.Person">
            <Annotation Term="Org.OData.Core.V1.Description" String="Attendees checked in at the front desk" />
        </EntitySet>
    </EntityContainer>
</Schema>
```

An undescribed element gets no annotation at all — the tag stays exactly as it was before this
feature existed (self-closed for an undescribed `<Member>`).

A property that carries both a description and a mutability annotation gets both children, in that
order — description first:

```xml
<Property Name="id" Nullable="false" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Description" String="Server-assigned identifier" />
    <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
```

XML special characters in a description are escaped (`&` → `&amp;`, `"` → `&quot;`, `<` → `&lt;`)
so the document stays well-formed.

### `$oas2`

A schema description becomes `info.description`; type descriptions land on the shared definition;
property descriptions land on each property within it. An entity-set description adds `summary`
(the same generated verb text used for the MCP tool of the same operation) and `description` to
every operation for that set — `GET` (collection and individual), `POST`, `PATCH`, and `DELETE`. A
set without a description keeps today's exact output: no `summary`, no `description` key on any of
its operations.

```jsonc
{
  "info": {
    "version": "1.0",
    "title": "Sample Service",
    "description": "Directory of people attending the annual conference"
  },
  "paths": {
    "/People": {
      "get": {
        "operationId": "GetCollectionOfPeople",
        "summary": "List People records",
        "description": "Attendees checked in at the front desk",
        "produces": ["application/json"]
      },
      "post": {
        "operationId": "CreatePeople",
        "summary": "Create a new People record",
        "description": "Attendees checked in at the front desk"
      }
    },
    "/People({id})": {
      "get":    { "summary": "Get a single People record by ID", "description": "Attendees checked in at the front desk" },
      "patch":  { "summary": "Update an existing People record",  "description": "Attendees checked in at the front desk" },
      "delete": { "summary": "Delete an existing People record",  "description": "Attendees checked in at the front desk" }
    }
  },
  "definitions": {
    "Gender": {
      "type": "string",
      "enum": ["Male", "Female"],
      "description": "Gender as recorded at registration"
    },
    "Person": {
      "type": "object",
      "description": "People present at the event",
      "properties": {
        "id":        { "type": "string", "readOnly": true },
        "user_name": { "type": "string", "description": "Unique login handle" },
        "name":      { "type": "string", "x-nullable": true, "description": "First name or full name" }
      }
    }
  }
}
```

The `PersonCreate` / `PersonUpdate` request-body definitions (see
[`doc/using_mutability.md`](using_mutability.md)) inherit property descriptions too, since they are
built from the same per-property rendering as the shared `Person` definition.

### MCP

Tool descriptions gain the entity set's description as a suffix, joined to the generated verb text
with `. ` — the verb stays first so an agent can still tell `list_` from `count_` from `delete_`:

```jsonc
// tools/list result for the People set
{
  "name": "list_People",
  "description": "List People records. Attendees checked in at the front desk",
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "odata_filter": { "type": "string", "description": "OData $filter expression" },
      "odata_select": { "type": "string", "description": "Comma-separated properties to return" }
    },
    "required": []
  }
}
```

This suffix appears on every tool for the set: `list_/get_/count_/create_/update_/delete_<Set>`.
Property descriptions reach the write and key tools' `inputSchema.properties`:

```jsonc
{
  "name": "create_People",
  "description": "Create a new People record. Attendees checked in at the front desk",
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "user_name": { "type": "string", "description": "Unique login handle" },
      "name":      { "type": "string", "x-nullable": true, "description": "First name or full name" }
    },
    "required": ["user_name"]
  }
}
```

The reserved `odata_*` query-option keys (see [`doc/using_mcp.md`](using_mcp.md)) keep their
existing framework descriptions; a property description never overwrites one — the
`InvalidMcpIdentifierError` collision check for a property that collides with a reserved key is
unaffected by whether either side has a `description:`.

A schema-level description becomes the server `instructions` in the `initialize` result:

```jsonc
// initialize result
{
  "protocolVersion": "2025-06-18",
  "capabilities": { "tools": {} },
  "serverInfo": { "name": "Sample Service", "version": "1.0" },
  "instructions": "Directory of people attending the annual conference"
}
```

Without a schema description, `instructions` is absent — exactly today's output.

## Common errors / edge cases

- **`OdataDuty::InvalidDescriptionError`** (an `ArgumentError` subclass) is raised at
  schema-definition time — when the class is loaded or the builder block runs, never at request
  time — when the description is:
  - an empty string — `description: ''`
  - whitespace-only — `description: '   '`
  - a value that does not respond to `to_str` — `description: :people`, `description: 123`,
    `description: ['a']`

  The message names the element, e.g. `Person: description must be a non-empty string`.

- **Omitting `description:` is never an error.** It is optional everywhere.
  **`description: nil` is treated the same as omitting it** — no annotation, no `$oas2` key, no MCP
  suffix — so a description interpolated from an optional source (e.g. a translation lookup that
  may miss) can be passed through without a guard.

- **`description:` never participates in request handling.** It cannot produce
  `InvalidQueryOptionError`, `UnknownPropertyError`, `InvalidValue`, or `InvalidType` — it plays no
  role in `$filter`, `$select`, `$search`, or create/update input coercion.

- **Three table cells above are intentionally empty, not bugs:**
  - **Enum member → `$oas2`**: Swagger 2.0 has no per-enum-value description slot, so a member
    description only ever reaches `$metadata`.
  - **Entity / complex / enum type → MCP**: MCP tools are entity-*set*-scoped, and the set
    description already suffixes every tool description for that set. Rendering the type
    description too would duplicate prose in the text an agent reads most.
  - **Schema → nothing else in MCP**: `serverInfo.description` exists in the `mcp` gem but is
    silently dropped (and can raise `ArgumentError` from `MCP::Server#validate!`) for negotiated
    protocol versions at or below `2025-06-18`. `instructions` is emitted at every protocol version,
    so it is the sole schema-level MCP target.

## Summary

- **`description:`** documents a schema, entity type, complex type, enum type, enum member,
  property (including `property_ref`), or entity set — always optional, `nil` treated as omitted.
- **One declaration, several targets:** it renders into `Org.OData.Core.V1.Description` in
  `$metadata`, the matching `description`/`info.description`/operation `summary`+`description` in
  `$oas2`, and tool/property descriptions plus server `instructions` in MCP — see the landing table
  above for exactly which contracts each element reaches.
- **Validated at definition time:** an empty, whitespace-only, or non-string value raises
  `OdataDuty::InvalidDescriptionError` naming the element; it never affects request handling.
