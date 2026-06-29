# Using property `mutability` with OdataDuty

Every property in OdataDuty sits somewhere on a **mutability** axis that controls whether a client may set it on **create**, on **update**, or never. The `mutability:` keyword on `property` (and `property_ref`) makes that explicit:

| `mutability:` | settable on create | settable on update | read response | OData term |
| --- | --- | --- | --- | --- |
| `:read_write` (default) | yes | yes | yes | none |
| `:immutable` | yes | **no** | yes | `Org.OData.Core.V1.Immutable` |
| `:computed` | **no** | **no** | yes | `Org.OData.Core.V1.Computed` |

This guide covers the `mutability:` axis with a focus on `:immutable` (set once on create, then frozen). For the dedicated read-only `:computed` case, see also [`doc/using_computed.md`](using_computed.md) — `computed:` is the `:computed` alias of this same axis.

> **Scope:** `mutability:` controls the **typed create/update input** only. Read responses are never affected — every property renders through the entity mapper regardless of its mutability.

## Overview

- **Purpose:** Declare per-property whether a client may set it on create, on update, or never — independent of whether it reads back.
- **Declaration:** `property 'account_number', String, mutability: :immutable`. Defaults to `:read_write`.
- **`:immutable`** is settable on **create**, ignored on **update**, and rendered in every read response.
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
  et.property 'created_at', DateTime, mutability: :computed
end
```

## The typed input honours mutability per operation

On `POST`/`PATCH` (or the MCP `create_<Set>` / `update_<Set>` tools), the request body is coerced into a typed input object and passed to your `create(input)` or `update(id, input)`. Which properties flow through depends on the operation:

- **On create**, `:immutable` and `:read_write` are coerced and present; `:computed` reads back `nil`.
- **On update**, only `:read_write` flows through; `:immutable` **and** `:computed` read back `nil`.

A dropped value is dropped **silently** — no error, not even `OdataDuty::InvalidType`, even for a value that would fail coercion for a writable property.

### On create

Given a request body:

```json
{ "account_number": "A-100", "note": "x", "created_at": "2021-01-01T00:00:00Z" }
```

inside `create`:

```ruby
def create(input)
  input.account_number  # => "A-100"  (immutable, settable on create)
  input.note            # => "x"       (read_write)
  input.created_at      # => nil       (computed, ignored)
  # ... assign created_at on the server, persist, and return the record
end
```

### On update

Given a request body:

```json
{ "account_number": "A-999", "note": "done" }
```

inside `update`:

```ruby
def update(id, input)
  input.note            # => "done"   (read_write, flows through)
  input.account_number  # => nil       (immutable, frozen on update — silently dropped)
  # ... merge note onto the existing record and return it
end
```

The supplied `account_number` is ignored on update; only `note` is applied. A wrong-typed immutable value (e.g. an integer for a `String`) is likewise dropped without raising.

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

### MCP

The `create_<Set>` tool's `inputSchema` includes `:read_write` and `:immutable` properties (and lists the non-nullable ones in `required`); `:computed` is absent. The `update_<Set>` tool keeps only the key and `:read_write` properties — `:immutable` **and** `:computed` are absent:

```jsonc
// tools/list — create includes the immutable property
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

// tools/list — update excludes immutable (and computed), keeping the key + read_write
{
  "name": "update_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":   { "type": "string" },
      "note": { "type": "string", "x-nullable": true }
    },
    "required": ["id"]
  }
}
```

### `$oas2` — not yet operation-aware (interim gap)

`$oas2` is **not** changed in this part. The `post` and `patch` operations still share one request body referencing the entity definition, where only `:computed` properties carry `readOnly: true`. An `:immutable` property therefore still appears writable in the `patch` body, even though the typed input drops it on update. This is a known, documented interim gap — the per-operation `$oas2` body split lands in a follow-up part.

## Common errors / edge cases

- **`property_ref` is computed by default.** A key is server-assigned unless you declare `property_ref 'id', String, mutability: :read_write` (or `computed: false`).
- **Both `mutability:` and `computed:` on one property** raises `ArgumentError` at schema-definition time:
  ``account_number: pass either `mutability:` or `computed:`, not both — they control the same axis``.
  `account_number: invalid mutability :frozen`.
- **A dropped value is a silent no-op** — an `:immutable` value on update, or a `:computed` value on either operation, reads back as `nil` with no error, even for a wrong-typed value.

## Summary

- **`mutability:`** is the per-property create/update axis: `:read_write` (default), `:immutable`, `:computed`.
- **`:immutable`** is set on create, frozen on update, and rendered in every read response; **`:computed`** is read-only on both.
- **`computed:` is a backward-compatible alias** (`true` ≡ `:computed`, `false` ≡ `:read_write`); keys default to `:computed`. Passing both keywords, or an unknown value, raises `ArgumentError`.
- **Reflected in** `$metadata` (`Core.Immutable` / `Core.Computed` / none) and MCP (create includes immutable, update excludes it). **`$oas2` is unchanged in this part** — an immutable property still appears writable in the shared body, addressed in a follow-up.
