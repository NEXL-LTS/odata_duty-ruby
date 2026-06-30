# Using property `mutability` with OdataDuty

Every property in OdataDuty sits somewhere on a **mutability** axis that controls whether a client may set it on **create**, on **update**, or never. The `mutability:` keyword on `property` (and `property_ref`) makes that explicit:

| `mutability:` | settable on create | settable on update | read response | OData term |
| --- | --- | --- | --- | --- |
| `:read_write` (default) | yes | yes | yes | none |
| `:immutable` | yes | **no** | yes | `Org.OData.Core.V1.Immutable` |
| `:non_insertable` | **no** | yes | yes | `Capabilities.InsertRestrictions/NonInsertableProperties` |
| `:computed` | **no** | **no** | yes | `Org.OData.Core.V1.Computed` |

This guide covers the `mutability:` axis with a focus on `:immutable` (set once on create, then frozen). For the dedicated read-only `:computed` case, see also [`doc/using_computed.md`](using_computed.md) — `computed:` is the `:computed` alias of this same axis.

> **Scope:** `mutability:` controls the **typed create/update input** only. Read responses are never affected — every property renders through the entity mapper regardless of its mutability.

## Overview

- **Purpose:** Declare per-property whether a client may set it on create, on update, or never — independent of whether it reads back.
- **Declaration:** `property 'account_number', String, mutability: :immutable`. Defaults to `:read_write`.
- **`:immutable`** is settable on **create**, ignored on **update**, and rendered in every read response.
- **`:non_insertable`** is the mirror image — settable on **update**, dropped on **create**, and rendered in every read response. It is reflected via the entity set's `Capabilities.InsertRestrictions/NonInsertableProperties` annotation, **not** a property-level `Core` annotation.
- **`:computed`** is settable on neither, but still rendered in reads — the read-only case documented in [`doc/using_computed.md`](using_computed.md).
- **Keys are computed by default:** `property_ref` defaults to `mutability: :computed`. Opt back in with `property_ref 'id', String, mutability: :read_write` (equivalently `computed: false`).
- **`computed:` is an alias:** `computed: true` ≡ `mutability: :computed`, `computed: false` ≡ `mutability: :read_write`. Passing both keywords raises `ArgumentError`.
- **Convention:** OdataDuty adopts OData Core vocabulary keyword names where practical — the terms mirror `Org.OData.Core.V1.Immutable` / `.Computed`.

## Declaring mutability

Both DSLs take the same `mutability:` keyword.

### Class DSL (`OdataDuty::EntityType`)

```ruby
class OrderEntity < OdataDuty::EntityType
  property_ref 'id', String, mutability: :read_write     # client-supplied key
  property 'account_number', String, nullable: false, mutability: :immutable  # set on create, then frozen
  property 'note', String                                 # :read_write (default)
  property 'status', String, mutability: :non_insertable  # set on update, not on create
  property 'created_at', DateTime, mutability: :computed   # server-assigned, read-only
end
```

### Builder DSL (`OdataDuty::SchemaBuilder`)

The builder DSL behaves identically:

```ruby
order_entity = s.add_entity_type(name: 'Order') do |et|
  et.property_ref 'id', String, mutability: :read_write
  et.property 'account_number', String, nullable: false, mutability: :immutable
  et.property 'note', String
  et.property 'status', String, mutability: :non_insertable
  et.property 'created_at', DateTime, mutability: :computed
end
```

## The typed input honours mutability per operation

On `POST`/`PATCH` (or the MCP `create_<Set>` / `update_<Set>` tools), the request body is coerced into a typed input object and passed to your `create(input)` or `update(id, input)`. Which properties flow through depends on the operation:

- **On create**, `:immutable` and `:read_write` are coerced and present; `:non_insertable` **and** `:computed` read back `nil`.
- **On update**, `:read_write` and `:non_insertable` are coerced and present; `:immutable` **and** `:computed` read back `nil`.

A dropped value is dropped **silently** — no error, not even `OdataDuty::InvalidType`, even for a value that would fail coercion for a writable property.

### On create

Given a request body:

```json
{ "account_number": "A-100", "note": "x", "status": "open", "created_at": "2021-01-01T00:00:00Z" }
```

inside `create`:

```ruby
def create(input)
  input.account_number  # => "A-100"  (immutable, settable on create)
  input.note            # => "x"       (read_write)
  input.status          # => nil       (non_insertable, dropped on create)
  input.created_at      # => nil       (computed, ignored)
  # ... assign status and created_at on the server, persist, and return the record
end
```

### On update

Given a request body:

```json
{ "account_number": "A-999", "note": "done", "status": "closed" }
```

inside `update`:

```ruby
def update(id, input)
  input.note            # => "done"   (read_write, flows through)
  input.status          # => "closed"  (non_insertable, settable on update)
  input.account_number  # => nil       (immutable, frozen on update — silently dropped)
  # ... merge note and status onto the existing record and return it
end
```

The supplied `account_number` is ignored on update; `note` and `status` are applied. A wrong-typed immutable value (e.g. an integer for a `String`) is likewise dropped without raising — symmetrically, a `:non_insertable` value behaves the same way on create.

## Reflected in the generated contracts

### Read responses (`GET`, `create`/`update` response) — unchanged

`:immutable` and `:computed` properties render in `collection`, `individual`, and the `create`/`update` response exactly like `:read_write` ones. Mutability changes nothing about what is read back.

### `$metadata` (EDMX)

The `<Property>` carries the matching Core annotation — `Immutable` or `Computed` — or none for `:read_write`:

```xml
<Property Name="account_number" Nullable="false" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />
</Property>
<Property Name="created_at" Nullable="true" Type="Edm.DateTimeOffset">
    <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
</Property>
<Property Name="note" Nullable="true" Type="Edm.String" />
```

The document references the `Org.OData.Core.V1` vocabulary (aliased `Core`) at the top:

```xml
<edmx:Reference Uri="https://docs.oasis-open.org/odata/odata-vocabularies/v4.0/vocabularies/Org.OData.Core.V1.xml">
    <edmx:Include Namespace="Org.OData.Core.V1" Alias="Core" />
</edmx:Reference>
```

`:non_insertable` is the exception — it carries **no** property-level `Core` annotation. Instead it is reflected at the entity set level: the property is listed as a `<PropertyPath>` inside a `NonInsertableProperties` `<Collection>` within the set's `Capabilities.InsertRestrictions` annotation:

```xml
<EntitySet Name="Orders" EntityType="MySpace.Order">
    <Annotation Term="Capabilities.InsertRestrictions">
        <Record>
            <PropertyValue Property="NonInsertableProperties">
                <Collection>
                    <PropertyPath>status</PropertyPath>
                </Collection>
            </PropertyValue>
        </Record>
    </Annotation>
</EntitySet>
```

This composes with the set-level `Insertable: false` (emitted when there is no `create`) in the same `<Record>`. The `Capabilities` vocabulary (aliased `Capabilities`) is already referenced at the top of the metadata document.

### MCP

The `create_<Set>` tool's `inputSchema` includes `:read_write` and `:immutable` properties (and lists the non-nullable ones in `required`); `:non_insertable` **and** `:computed` are absent. The `update_<Set>` tool keeps the key, `:read_write`, and `:non_insertable` properties — `:immutable` **and** `:computed` are absent:

```jsonc
// tools/list — create includes the immutable property, excludes non_insertable + computed
{
  "name": "create_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "account_number": { "type": "string" },
      "note":           { "type": "string", "x-nullable": true }
    },
    "required": ["account_number"]
  }
}

// tools/list — update includes non_insertable (status), excludes immutable + computed
{
  "name": "update_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":     { "type": "string" },
      "status": { "type": "string" },
      "note":   { "type": "string", "x-nullable": true }
    },
    "required": ["id"]
  }
}
```

### `$oas2`

`$oas2` emits **three** definitions per writable entity, and the operation bodies are mapped per operation. The `<Entity>` definition is the full response shape — every property, with `:computed` carrying `readOnly: true` and nullable properties carrying `x-nullable: true`. The `post` body references `<Entity>Create` (`:read_write` + `:immutable`; `:computed` and `:non_insertable` omitted) and the `patch` body references `<Entity>Update` (`:read_write` + `:non_insertable`; `:computed` and `:immutable` omitted — the key travels in the path). Responses (and all `GET` / `collection` / `individual` reads) reference `<Entity>`. `<Entity>Create` lists its non-nullable create-settable properties in `required`; `<Entity>Update` has no `required` (PATCH is partial-merge):

```jsonc
// definitions — three shapes for the Order entity
{
  "Order": {
    "type": "object",
    "properties": {
      "id":             { "type": "string", "readOnly": true },
      "account_number": { "type": "string" },
      "note":           { "type": "string", "x-nullable": true },
      "status":         { "type": "string", "x-nullable": true },
      "created_at":     { "type": "string", "readOnly": true, "x-nullable": true }
    }
  },
  "OrderCreate": {
    "type": "object",
    "properties": {
      "account_number": { "type": "string" },
      "note":           { "type": "string", "x-nullable": true }
    },
    "required": ["account_number"]
  },
  "OrderUpdate": {
    "type": "object",
    "properties": {
      "note":   { "type": "string", "x-nullable": true },
      "status": { "type": "string", "x-nullable": true }
    }
  }
}
```

The per-operation bodies are emitted for **every** writable set, even one with no constrained properties (where `<Entity>Create` / `<Entity>Update` simply equal the writable set). `x-ms-mutability` is **not** emitted: it is an AutoRest SDK extension that Power Automate / Logic Apps custom connectors do not honour — they consume the separate Create and Update actions with their separate bodies instead, and `readOnly` covers the computed case in the `<Entity>` response.

## Common errors / edge cases

- **`property_ref` is computed by default.** A key is server-assigned unless you declare `property_ref 'id', String, mutability: :read_write` (or `computed: false`).
- **Both `mutability:` and `computed:` on one property** raises `ArgumentError` at schema-definition time:
  ``account_number: pass either `mutability:` or `computed:`, not both — they control the same axis``.
- **An unknown `mutability:` value** raises `ArgumentError` at schema-definition time, listing all four valid values: `bad: invalid mutability :frozen, must be one of :read_write, :immutable, :non_insertable, :computed`.
- **A dropped value is a silent no-op** — an `:immutable` value on update, a `:non_insertable` value on create, or a `:computed` value on either operation, reads back as `nil` with no error, even for a wrong-typed value.

## Summary

- **`mutability:`** is the per-property create/update axis: `:read_write` (default), `:immutable`, `:non_insertable`, `:computed`.
- **`:immutable`** is set on create, frozen on update; **`:non_insertable`** is the mirror — dropped on create, settable on update; **`:computed`** is read-only on both. All three still render in every read response.
- **`computed:` is a backward-compatible alias** (`true` ≡ `:computed`, `false` ≡ `:read_write`); keys default to `:computed`. Passing both keywords, or an unknown value, raises `ArgumentError`.
- **Reflected in** `$metadata` (`Core.Immutable` / `Core.Computed` / none, plus `Capabilities.InsertRestrictions/NonInsertableProperties` for `:non_insertable`) and MCP (create excludes non_insertable + computed, update excludes immutable + computed). **`$oas2`** now emits per-operation `<Entity>Create` / `<Entity>Update` request bodies (create excludes computed + non_insertable; update excludes computed + immutable) alongside the full `<Entity>` response, where `:computed` is `readOnly`.
