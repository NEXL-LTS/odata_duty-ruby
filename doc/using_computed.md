# Using `computed` (read-only) properties with OdataDuty

A **computed** property is one that the server generates — an auto-incrementing key, a `created_at` timestamp, a derived field. It still appears in every read response, but clients must not (and cannot) set it when creating a record. OdataDuty marks such a property with the `computed:` keyword on `property`. A computed property renders normally in `GET`/`collection`/`individual`/`create` responses but is excluded from the **create/update input** surface across all three contracts.

This guide explains how to declare a computed property in both DSLs and how the read-only distinction is reflected in the generated `$metadata`, `$oas2`, MCP, and the typed `create` input.

> **Alias:** `computed:` is now the `:computed` alias of the broader `mutability:` axis (`computed: true` ≡ `mutability: :computed`, `computed: false` ≡ `mutability: :read_write`). Everything here still works unchanged. For the `:immutable` case (settable on create, frozen on update) and the full axis, see [`doc/using_mutability.md`](using_mutability.md).
>
> **Scope:** `computed:` controls the **typed create/update input** — a computed property is settable on neither. The term mirrors the OData `Org.OData.Core.V1.Computed` vocabulary annotation.

## Overview

- **Purpose:** Mark a property server-generated / read-only so clients can read it but never supply it on create.
- **Declaration:** `property 'created_at', DateTime, computed: true`. The keyword defaults to `false` (writable).
- **Keys are computed by default:** `property_ref` defaults to `computed: true` (a server-assigned key). Opt back in with `property_ref 'id', String, computed: false`.
- **Read responses unchanged:** A computed property is rendered in `collection`, `individual`, and the `create` response exactly like any other property.
- **Excluded from create input:** It is absent from the MCP `create_<Set>` tool's `inputSchema`, carries `readOnly: true` in `$oas2`, and the typed `create` input object returns `nil` for it regardless of the request body.
- **Convention:** OdataDuty adopts OData Core vocabulary keyword names where practical — `computed:` mirrors `Org.OData.Core.V1.Computed`.

## Declaring a computed property

Both DSLs take the same `computed:` keyword.

### Class DSL (`OdataDuty::EntityType`)

```ruby
class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String                          # key: computed: true by default
  property 'user_name', String, nullable: false      # writable
  property 'created_at', DateTime, computed: true     # read-only, server-assigned
end
```

To make the key writable (client-supplied) instead, opt back in explicitly:

```ruby
property_ref 'id', String, computed: false
```

### Builder DSL (`OdataDuty::SchemaBuilder`)

The builder DSL behaves identically:

```ruby
person_entity = s.add_entity_type(name: 'Person') do |et|
  et.property_ref 'id', String                        # key: computed: true by default
  et.property 'user_name', String, nullable: false    # writable
  et.property 'created_at', DateTime, computed: true   # read-only, server-assigned
end
```

## The typed `create` input drops computed values

On `POST` (or the MCP `create_<Set>` tool), the request body is coerced into a typed input object and passed to your `create`. Computed properties are stripped from that object: reading one returns `nil` no matter what the body contained, and a wrong-typed computed value is dropped **silently** — no error, not even `OdataDuty::InvalidType`.

Given a request body:

```json
{ "id": "999", "user_name": "alice", "created_at": "2021-01-01T00:00:00Z" }
```

inside `create`:

```ruby
def create(input)
  input.user_name   # => "alice"   (writable, coerced normally)
  input.id          # => nil        (computed key, ignored)
  input.created_at  # => nil        (computed, ignored)
  # ... assign id / created_at on the server, persist, and return the record
end
```

Both the supplied `id` and `created_at` are ignored; only `user_name` flows through. The record your `create` returns is rendered through the entity type's mapper, so the response **does** include the server-assigned `id` and `created_at`.

## Reflected in the generated contracts

### Read responses (`GET`, `create` response) — unchanged

Computed properties render in `collection`, `individual`, and the `create` response exactly like writable ones. Marking a property `computed:` changes nothing about what is read back.

### `$metadata` (EDMX)

A computed `<Property>` carries the `Org.OData.Core.V1.Computed` annotation:

```xml
<Property Name="created_at" Nullable="true" Type="Edm.DateTimeOffset">
    <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
```

A writable property gets no such annotation. Because the key is computed by default, its `<Property>` carries the same annotation unless declared `computed: false`.

The document references the `Org.OData.Core.V1` vocabulary (aliased `Core`) at the top:

```xml
<edmx:Reference Uri="https://docs.oasis-open.org/odata/odata-vocabularies/v4.0/vocabularies/Org.OData.Core.V1.xml">
    <edmx:Include Namespace="Org.OData.Core.V1" Alias="Core" />
</edmx:Reference>
```

### `$oas2`

A computed property is marked `readOnly: true` in the shared entity definition:

```jsonc
{
  "definitions": {
    "Person": {
      "properties": {
        "id":         { "type": "string", "readOnly": true },
        "user_name":  { "type": "string" },
        "created_at": { "type": "string", "format": "date-time", "readOnly": true, "x-nullable": true }
      }
    }
  }
}
```

The `post` body still references the shared `#/definitions/Person`; `readOnly: true` is the OAS2 signal that the field is response-only.

### MCP

The `create_<Set>` tool's `inputSchema` lists only writable properties — computed ones are absent from both `properties` and `required`:

```jsonc
// tools/list result for a set with a computed `id` and `created_at`
{
  "name": "create_Person",
  "description": "Create a new Person record",
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "user_name": { "type": "string" }
    },
    "required": ["user_name"]
  }
}
```

`id` and `created_at` never appear in the create tool's input, so an agent cannot supply them.

## Common errors / edge cases

- **A computed value supplied on create is silently dropped.** Whether well-typed or wrong-typed, a computed value in the request body is ignored — no error is raised, and there is no `OdataDuty::InvalidType` even for a value that would fail coercion for a writable property. The typed input reads it back as `nil`.
- **`property_ref` is computed by default.** A key is server-assigned unless you declare `property_ref 'id', String, computed: false`. If clients must supply the key, opt out explicitly.
- **Opt back in with `computed: false`.** This restores a property (including a key) to the writable surface: it reappears in the MCP `create_<Set>` `inputSchema`, drops `readOnly` in `$oas2`, loses the `Core.Computed` annotation in `$metadata`, and is coerced onto the typed `create` input.

## Summary

- **Mark a property read-only** with `property 'created_at', DateTime, computed: true` (default `false`); keys (`property_ref`) are computed by default — opt out with `computed: false`.
- **Computed properties render normally** in every read response but are dropped from the create input: absent from the MCP `create_<Set>` `inputSchema`, `readOnly: true` in `$oas2`, annotated `Org.OData.Core.V1.Computed` in `$metadata`, and `nil` on the typed `create` input.
- **Supplying a computed value on create is a silent no-op** — never an error, even for a wrong-typed value.
