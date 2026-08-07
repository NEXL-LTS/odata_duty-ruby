# PRD: `description` — human-readable documentation on every schema element

## Summary

Let a gem consumer attach a `description:` to a schema, entity type, complex type, enum type, enum member, property, and entity set, and have that prose surface automatically in `$metadata` (as `Org.OData.Core.V1.Description`), in `$oas2`, and in the MCP tool and server metadata that an LLM reads.

## Goal / Problem

OdataDuty generates four consumer-facing contracts from one Ruby schema, and today **none of them can carry a word of author-supplied prose**. The only human-readable metadata the DSL accepts is schema-level `title` and `version`.

Every `description` string in the current output is a hardcoded framework constant — `'Collection Response'`, `'Number of results to return'`, `"List People records"`. A consumer who wants to explain that `name` means "first name or full name", or that the `People` set holds "people present at the event", has nowhere to put it.

Concretely, today:

```ruby
class PersonEntity < OdataDuty::EntityType
  description 'People present at the event'      # NoMethodError: undefined method `description'
  property 'name', String, description: 'First name or full name'  # ArgumentError: unknown keyword: :description
end
```

Both DSLs fail the same way — `Property.new` takes an explicit keyword list, `SchemaBuilder::DataType#initialize` takes only `name:`, and `SchemaBuilder::EntitySet#initialize` takes only `entity_type/resolver/name/url/init_args`.

This hurts three audiences:

- **OData clients** (Excel, Power BI, Power Automate) read `Core.Description` from `$metadata` to label fields in their UI. Without it, users see raw property names.
- **Swagger consumers** get a `$oas2` document whose definitions and operations are entirely unannotated.
- **LLM agents** over MCP pick tools by reading `description`. `"List People records"` tells a model nothing about what a `People` record *is* — which is the single highest-leverage gap, because tool descriptions are the primary input to tool selection.

Expected behavior after this change: one `description:` declaration per element propagates to every contract that has a slot for it, with no per-format duplication.

## What it enables

- As a gem consumer, I can write `property 'name', String, description: 'First name or full name'` and have that text appear in `$metadata`, in the `$oas2` `Person` definition, and as the argument description on the MCP `create_People` / `update_People` tools — from one declaration.
- As a gem consumer, I can describe an entity set once and have that description enrich **every** MCP tool for that set (`list_`, `count_`, `get_`, `create_`, `update_`, `delete_`) so an agent understands the domain, not just the verb.
- As a gem consumer, I can give my whole service a description that reaches Swagger UI's header and the MCP client's `instructions`, so an agent is oriented before it calls a single tool.
- As a gem consumer, I can document enum members so a client UI can explain what `Male` / `Female` / `Unknown` mean in my domain.
- As a gem consumer building the schema at runtime from request data, I get the identical capability in the builder DSL.

**Scope limit:** this covers the OData `Core.Description` (short form) only. `Core.LongDescription` is out of scope — see *Scope*.

## External API

A single new keyword, `description:`, spelled the same way at every level. It is always optional; omitting it leaves output byte-identical to today.

The name mirrors the OData Core vocabulary term **`Org.OData.Core.V1.Description`**, following the same convention the gem already uses for `computed:` (`Core.Computed`) and `mutability: :immutable` (`Core.Immutable`).

### Class-based DSL

Type-level descriptions use a class macro (matching the existing `namespace` / `title` / `version` / `entity_type` / `url` macros); property- and member-level use a keyword.

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
  property_ref 'id', String
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

Like the other class macros, `description` is a reader when called with no argument: `PersonEntity.description # => "People present at the event"`.

### Builder DSL

The builder DSL takes `description:` as a keyword on each `add_*` call, and on `property` / `property_ref` / `member`. Schema-level uses an accessor, matching the existing `title` / `version`.

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
    et.property_ref 'id', String
    et.property 'user_name', String, nullable: false, description: 'Unique login handle'
    et.property 'name', String, description: 'First name or full name'
    et.property 'gender', gender
    et.property 'address', address
  end

  s.add_entity_set(entity_type: person, resolver: 'PeopleResolver', name: 'People',
                   description: 'Attendees checked in at the front desk')
end
```

### Where each description lands

| Declared on | `$metadata` (EDMX) | `$oas2` | MCP |
| --- | --- | --- | --- |
| Schema | `Org.OData.Core.V1.Description` annotation on `<Schema>` | `info.description` | `instructions` in the `initialize` result |
| Entity type | `Org.OData.Core.V1.Description` on `<EntityType>` | `definitions.<Type>.description` | — |
| Complex type | `Org.OData.Core.V1.Description` on `<ComplexType>` | `definitions.<Type>.description` | — |
| Enum type | `Org.OData.Core.V1.Description` on `<EnumType>` | `definitions.<Type>.description` | — |
| Enum member | `Org.OData.Core.V1.Description` on `<Member>` | — | — |
| Property | `Org.OData.Core.V1.Description` on `<Property>` | `definitions.<Type>.properties.<name>.description` | `inputSchema.properties.<name>.description` on every tool exposing that property |
| Entity set | `Org.OData.Core.V1.Description` on `<EntitySet>` | operation `summary` + `description` | appended to each tool's `description` |

Three cells are intentionally empty:

- **Enum member → `$oas2`**: Swagger 2.0 has no per-enum-value description slot. `$metadata` only.
- **Entity / complex / enum type → MCP**: MCP tools are entity-*set*-scoped, and the set description already suffixes every tool description. Adding the type description too would duplicate prose in the text an agent reads most.
- **Schema → nothing else**: `serverInfo.description` exists in `mcp` 0.25.0 but is silently dropped for negotiated protocol version ≤ `2025-06-18`, and `MCP::Server#validate!` raises `ArgumentError` on it in that range. `instructions` is emitted at every protocol version, so it is the sole schema-level MCP target.

The OData service document (`index_hash`) is unchanged: its entries stay `{name, kind, url}`. OData's service-document `title` is a display name, not a description, so it is not populated from `description:`.

## Behavior & expected I/O

All "before" output below is the gem's current, verified output for the schema in *External API*.

### `$metadata` (EDMX)

The document already declares the `Org.OData.Core.V1` vocabulary with alias `Core` at the top, so no new `<edmx:Reference>` is needed.

Before:

```xml
<Schema Namespace="Sample" xmlns="http://docs.oasis-open.org/odata/ns/edm">
    <Annotation Term="Sample.Version" String="1.0" />
    <Annotation Term="Sample.Title" String="Sample Service" />
    <EnumType Name="Gender">
        <Member Name="Male" />
        <Member Name="Female" />
    </EnumType>
    <EntityType Name="Person">
        <Key><PropertyRef Name="id" /></Key>
        <Property Name="user_name" Nullable="false" Type="Edm.String" />
        <Property Name="name" Nullable="true" Type="Edm.String" />
    </EntityType>
    <EntityContainer Name="Container">
        <EntitySet Name="People" EntityType="Sample.Person" />
    </EntityContainer>
</Schema>
```

After:

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

A property that carries both a description and a mutability annotation gets both children, in that order:

```xml
<Property Name="id" Nullable="false" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Description" String="Server-assigned identifier" />
    <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
```

XML special characters in a description are escaped (`&` → `&amp;`, `"` → `&quot;`, `<` → `&lt;`) so the document stays well-formed.

### `$oas2`

Before:

```jsonc
{
  "info": { "version": "1.0", "title": "Sample Service" },
  "paths": {
    "/People": {
      "get": {
        "operationId": "GetCollectionOfPeople",
        "produces": ["application/json"],
        "parameters": [ /* ... */ ]
      }
    }
  },
  "definitions": {
    "Person": {
      "type": "object",
      "properties": {
        "id":        { "type": "string", "readOnly": true },
        "user_name": { "type": "string" },
        "name":      { "type": "string", "x-nullable": true }
      }
    }
  }
}
```

After:

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
        "produces": ["application/json"],
        "parameters": [ /* ... */ ]
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

`summary` is the same generated verb text used for the MCP tool of the same operation, so the two contracts stay consistent. Operations get a `summary` **only** when the set has a description; a set without one keeps today's exact output (no `summary`, no `description`).

The `PeopleCreate` / `PeopleUpdate` request-body definitions inherit property descriptions, since they are built from the same per-property rendering as the shared `Person` definition.

### MCP

Tool descriptions gain the set description as a suffix, joined to the generated text with `. ` — the verb stays first so an agent can still tell `list_` from `count_` from `delete_`.

Before:

```jsonc
{
  "name": "list_People",
  "description": "List People records",
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

After:

```jsonc
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

Property descriptions reach the write and key tools:

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

The reserved `odata_*` query-option keys keep their existing framework descriptions; a property description never overwrites one (the existing `InvalidMcpIdentifierError` collision check is unaffected).

Schema-level description becomes the server `instructions`:

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

### Read and write responses are unchanged

`description:` is pure metadata. Collection JSON, individual JSON, `/$count`, and the create/update/delete responses are byte-identical whether or not descriptions are declared, and no description ever appears in a data payload.

## Common error cases

Descriptions are validated at schema-definition time, so a bad one fails when the class is loaded or the builder block runs — never at request time.

- **`OdataDuty::InvalidDescriptionError`** (a new `ArgumentError` subclass, matching `InvalidNCNamesError` and `PropertyAlreadyDefinedError`) is raised when:
  - the description is an empty string — `description: ''`
  - the description is whitespace-only — `description: '   '`
  - the value does not respond to `to_str` — `description: :people`, `description: 123`, `description: ['a']`

  The message names the element, e.g. `Person: description must be a non-empty string`.

- **Omitting `description:` is never an error.** It is optional everywhere. `description: nil` is treated the same as omitting it — no annotation, no `$oas2` key, no MCP suffix — so a description interpolated from an optional source can be passed through without a guard.

- **No new request-time errors.** `description:` does not participate in `$filter`, `$select`, `$search`, or create/update input coercion, so it cannot produce `InvalidQueryOptionError`, `UnknownPropertyError`, `InvalidValue`, or `InvalidType`.

- **Existing errors are unaffected.** `PropertyAlreadyDefinedError` still fires on a duplicate property name regardless of descriptions; `InvalidNCNamesError` still fires on an invalid property name and is raised *before* the description is validated.

## Scope

**In scope**

- A `description:` keyword / macro on: schema, entity type, complex type, enum type, enum member, property (including `property_ref`), and entity set.
- **Both DSLs** — class-based (`OdataDuty::EntityType` / `ComplexType` / `EnumType` / `EntitySet` / `Schema`) and builder (`OdataDuty::SchemaBuilder`) — with matching behavior and matching spec coverage under `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`.
- Rendering into `$metadata`, `$oas2` (`info`, definitions, properties, operations), and MCP (tool descriptions, input-schema property descriptions, server `instructions`).
- Validation and its error class.

**Out of scope**

- **`Org.OData.Core.V1.LongDescription`.** One `description:` field only. A future `long_description:` would be purely additive.
- **Localisation.** A description is a single string; no per-locale variants and no `Core.Messages`-style structures.
- **Descriptions on framework-generated output that is not author-owned** — the `Error` definition, the `odata_*` query-option parameters, and OAS2 response descriptions (`'Collection Response'`, `'Unexpected error'`) keep their current hardcoded text.
- **The service/index document.** `index_hash` entries stay `{name, kind, url}`.
- **Descriptions on navigation properties or actions/functions.** The gem does not expose those today.
- **Rails generator templates.** The generators are not updated to emit `description:` scaffolding.
- **Any change to read/write request handling.** No new query option, no new `od_*` hook.

## Documentation impact

Add a **new guide**, `doc/using_descriptions.md`, in the style of `doc/using_computed.md` and `doc/using_mutability.md`: purpose-first, both-DSL snippets, a section per output contract (`$metadata` / `$oas2` / MCP) showing the rendered result, and a closing "Common errors / edge cases" section. The where-each-description-lands table above should carry over.

Also update:

- **`CLAUDE.md`** — add a `**Descriptions**` bullet to the Features list pointing at the new guide.
- **`README.md`** — add `description:` to the entity-type / property example so it is visible in the first schema a reader sees.
- **`doc/using_mcp.md`** — note that tool descriptions incorporate the entity-set description and that a schema description becomes the server `instructions`.
- **`doc/using_oas2.md`** — note the new `info.description`, definition, property, and operation `summary`/`description` output.
