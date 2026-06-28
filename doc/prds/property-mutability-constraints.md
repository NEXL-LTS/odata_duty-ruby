# PRD: Per-property mutability (`create`-only and `update`-only fields)

## Summary

Give gem consumers a single per-property `mutability:` keyword that controls **when** a
property may be written: on create only (then frozen), on update only (never on create),
on both, or never. This generalizes today's binary `computed:` flag into a four-state axis
and mirrors the OData `Core.Immutable` / `Core.Computed` / `Capabilities.*Restrictions`
vocabulary, so the same declaration drives the typed `create`/`update` input, `$metadata`,
`$oas2`, and the MCP create/update tools.

## Goal / Problem

Today a property is either fully writable or `computed: true` (read-only — excluded from
**both** create and update input). There is no way to express the two most common
real-world write constraints:

- **"Settable on create, frozen after."** A value the client supplies once at creation
  and must never change afterward — an external reference id, an owner, an account number.
  OData calls this `Core.Immutable`.
- **"Settable on update, not on create."** A value that does not exist at creation time and
  is only ever assigned later — a lifecycle `status`, a `closed_at`, a `verified_by`. OData
  expresses this as `Capabilities.InsertRestrictions/NonInsertableProperties`.

A consumer who needs either today must hand-roll the guard inside `create`/`update` and gets
no help in the generated contracts: `$metadata`, `$oas2`, and the MCP tool input schemas all
advertise the field as freely writable, so clients and agents are told they may send values
the server will reject or silently discard. The `computed:` guide already anticipates this —
it notes the flag is "forward-compatible with a future update path." This PRD is that path.

## What it enables

- *As a gem consumer, I can declare* `property 'created_at', DateTime, mutability: :immutable`
  *so the field is accepted on create, ignored on update, and advertised as immutable
  everywhere.*
- *As a gem consumer, I can declare* `property 'status', String, mutability: :update_only`
  *so the field is ignored on create, accepted on PATCH, and advertised as insert-restricted.*
- *As a gem consumer, I keep* `mutability: :read_only` *(or the existing `computed: true`
  alias) for server-generated fields — behavior is unchanged.*
- *As an MCP client / agent, the `create_<Set>` and `update_<Set>` tool input schemas only
  ever list the fields actually settable for that operation,* so I cannot be misled into
  sending a value that will be dropped.

Scope limits: mutability is **static** per property — there is no state-dependent or
role-dependent ("immutable once approved") variant. Enforcement is at the typed-input layer
(the value is dropped before your `create`/`update` sees it); persistence-level guarantees
remain the consumer's responsibility.

## External API

### The `mutability:` keyword

A new keyword on `property` and `property_ref`, taking one of four symbols:

| `mutability:` | Settable on create | Settable on update | Read response | OData term |
|---|:---:|:---:|:---:|---|
| `:read_write` (**default**) | ✅ | ✅ | ✅ | *(none)* |
| `:immutable` | ✅ | ❌ | ✅ | `Core.Immutable` |
| `:update_only` | ❌ | ✅ | ✅ | `Capabilities.InsertRestrictions/NonInsertableProperties` |
| `:read_only` | ❌ | ❌ | ✅ | `Core.Computed` |

- The default is `:read_write` (a plain writable property), matching today's default.
- **`computed: true` is retained as a backwards-compatible alias for `mutability: :read_only`**;
  `computed: false` aliases `:read_write`. Existing schemas keep working unchanged.
- **`property_ref` (keys) default to `mutability: :read_only`** — exactly today's
  "keys are computed by default." Opt a key into client-supplied with
  `property_ref 'id', String, mutability: :read_write` (equivalently `computed: false`).
- Specifying **both** `mutability:` and `computed:` on the same property is an error
  (see Common error cases).

### Class DSL (`OdataDuty::EntityType`)

```ruby
class OrderEntity < OdataDuty::EntityType
  property_ref 'id', String                                   # key: :read_only by default
  property 'account_number', String, mutability: :immutable    # set on create, frozen after
  property 'status',         String, mutability: :update_only  # not on create, set later
  property 'created_at',     DateTime, mutability: :read_only   # server-assigned (== computed)
  property 'note',           String                            # :read_write (default)
end
```

### Builder DSL (`OdataDuty::SchemaBuilder`)

Identical keyword on the builder's `property` / `property_ref`:

```ruby
order_entity = s.add_entity_type(name: 'Order') do |et|
  et.property_ref 'id', String                                   # key: :read_only by default
  et.property 'account_number', String, mutability: :immutable
  et.property 'status',         String, mutability: :update_only
  et.property 'created_at',     DateTime, mutability: :read_only
  et.property 'note',           String
end
```

### Hook contract

No new hooks. The existing `create(input)` and `update(id, input)` are unchanged in
signature; what changes is **which fields carry a value** on the typed `input` object:

- Inside `create(input)`, a property not settable on create (`:read_only`, `:update_only`)
  reads back as `nil` regardless of the request body.
- Inside `update(id, input)`, a property not settable on update (`:read_only`, `:immutable`)
  reads back as `nil` regardless of the request body — over and above the existing
  partial-merge rule (omitted fields already read as `nil`).

## Behavior & expected I/O

### Typed input — disallowed values are silently ignored

Consistent with how `computed:` behaves on create today, a value the client is not allowed to
set for the current operation is **silently dropped** — no error, and no `InvalidType` even
for a wrong-typed value. The typed input reads it back as `nil`.

`POST /Orders` with body:

```json
{ "account_number": "A-100", "status": "open", "created_at": "2030-01-01T00:00:00Z" }
```

inside `create`:

```ruby
def create(input)
  input.account_number  # => "A-100"  (:immutable — settable on create)
  input.status          # => nil       (:update_only — ignored on create)
  input.created_at      # => nil       (:read_only — ignored on create)
  input.note            # => nil       (:read_write, absent from body)
  # assign id/status/created_at on the server, persist, return the record
end
```

`PATCH /Orders('1')` with body:

```json
{ "account_number": "A-999", "status": "closed", "note": "done" }
```

inside `update`:

```ruby
def update(id, input)
  input.account_number  # => nil       (:immutable — frozen on update, ignored)
  input.status          # => "closed"  (:update_only — settable on update)
  input.note            # => "done"    (:read_write)
  input.created_at      # => nil       (:read_only — ignored on update)
end
```

Read responses (`collection`, `individual`, and the `create`/`update` response bodies) are
**unchanged**: every property, regardless of mutability, renders through the entity mapper
exactly as today.

### `$metadata` (EDMX)

- `:read_only` → `Org.OData.Core.V1.Computed` on the `<Property>` (unchanged from today).
- `:immutable` → `Org.OData.Core.V1.Immutable` on the `<Property>`:

```xml
<Property Name="account_number" Nullable="true" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />
</Property>
```

- `:update_only` → the entity set's `Capabilities.InsertRestrictions` annotation gains a
  `NonInsertableProperties` collection listing the property path. This composes with the
  existing set-level `Insertable: false` annotation (emitted when there is no `create`):

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

- `:read_write` → no annotation (unchanged).

The `Core` and `Capabilities` vocabularies are already referenced at the top of the metadata
document, so no new references are needed.

### `$oas2`

In the shared entity definition, mutability maps to the standard `readOnly` plus the
widely-used `x-ms-mutability` vendor extension (Swagger 2.0 has no native immutable concept):

```jsonc
{
  "definitions": {
    "Order": {
      "properties": {
        "id":             { "type": "string", "readOnly": true, "x-ms-mutability": ["read"] },
        "account_number": { "type": "string", "x-ms-mutability": ["create", "read"] },
        "status":         { "type": "string", "x-ms-mutability": ["read", "update"] },
        "created_at":     { "type": "string", "format": "date-time", "readOnly": true,
                            "x-ms-mutability": ["read"] },
        "note":           { "type": "string" }
      }
    }
  }
}
```

- `:read_only` → `readOnly: true` (unchanged) **and** `x-ms-mutability: ["read"]`.
- `:immutable` → `x-ms-mutability: ["create", "read"]` (no `readOnly`).
- `:update_only` → `x-ms-mutability: ["read", "update"]` (no `readOnly`).
- `:read_write` → neither key (unchanged).

### MCP

- `create_<Set>` `inputSchema` lists only properties **settable on create** (`:read_write` +
  `:immutable`); `:read_only` and `:update_only` are absent from both `properties` and
  `required`. `required` is the non-nullable subset of those.
- `update_<Set>` `inputSchema` lists the key plus only properties **settable on update**
  (`:read_write` + `:update_only`); `:read_only` and `:immutable` are absent. `required` is
  the key only (partial-merge), and the key keeps `readOnly: true`.

```jsonc
// tools/list — create tool: status (:update_only) and created_at/id (:read_only) absent
{
  "name": "create_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "account_number": { "type": "string", "x-ms-mutability": ["create", "read"] },
      "note":           { "type": "string" }
    },
    "required": ["account_number"]
  }
}
```

```jsonc
// tools/list — update tool: account_number (:immutable) and created_at (:read_only) absent
{
  "name": "update_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":     { "type": "string", "readOnly": true, "x-ms-mutability": ["read"] },
      "status": { "type": "string", "x-ms-mutability": ["read", "update"] },
      "note":   { "type": "string" }
    },
    "required": ["id"]
  }
}
```

## Common error cases

- **Disallowed value supplied → silently ignored.** A value for a property not settable in
  the current operation (an `:immutable`/`:read_only` field on PATCH, an
  `:update_only`/`:read_only` field on POST) is dropped — no error, and no
  `OdataDuty::InvalidType` even for a wrong-typed value. The typed input reads it as `nil`.
  This matches today's `computed:` behavior exactly.
- **Unknown `mutability:` value → declaration-time error.** Passing a symbol outside
  `{:read_write, :immutable, :update_only, :read_only}` (e.g. `mutability: :frozen`) raises
  an `ArgumentError` when the schema is defined, naming the property and the bad value.
- **Both `mutability:` and `computed:` on one property → declaration-time error.** Specifying
  both keywords raises an `ArgumentError` (they control the same axis); pick one.
- **Wrong-typed value for an *allowed* field → unchanged.** A value that fails coercion for a
  property that *is* settable in the current operation still raises `OdataDuty::InvalidType`,
  exactly as today.
- **Accessing a non-property on the typed input → unchanged.** Still raises
  `OdataDuty::NoSuchPropertyError`.

## Scope

**In scope**

- A `mutability:` keyword on `property` and `property_ref` in **both** DSLs (class-based and
  builder), with `computed:` retained as a `:read_only`/`:read_write` alias and keys
  defaulting to `:read_only`.
- Enforcement (silent drop) in the typed `create` and `update` input objects.
- Reflection across `$metadata` (`Core.Immutable`, `Core.Computed`,
  `Capabilities.InsertRestrictions/NonInsertableProperties`), `$oas2` (`readOnly` +
  `x-ms-mutability`), and the MCP `create_<Set>` / `update_<Set>` tool input schemas.
- Matching specs under **both** `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**`.

**Out of scope**

- State-dependent or role-dependent mutability ("immutable only once approved").
- Persistence-level enforcement — dropping the value from the typed input is the guarantee;
  what the consumer's `create`/`update` does with the record is theirs.
- Navigation/relationship properties (the gem has none today).
- Any change to read rendering — every property still renders in read responses.

## Documentation impact

Add a new guide **`doc/using_mutability.md`** in the house style covering the full four-state
`mutability:` axis, the create/update/read matrix, and the reflection across all four
contracts. Update **`doc/using_computed.md`** to state that `computed:` is now the
`:read_only` alias of `mutability:` and link to the new guide (it already flags itself as
forward-compatible with the update path). Cross-reference from
**`doc/using_create_update_and_delete.md`** where it discusses the typed create/update input.
Refresh the `## Features` index in `CLAUDE.md` with a one-line entry pointing at the new
guide.

## Open questions

- **`$oas2` immutable representation.** This PRD proposes the de-facto `x-ms-mutability`
  vendor extension since Swagger 2.0 has no native immutable keyword. If a different
  convention is preferred (e.g. omit the hint entirely and rely on `$metadata` for the
  immutable/insert-restricted distinction), that narrows the `$oas2` work.
- **`NonUpdatableProperties` for `:immutable`.** The PRD uses the dedicated `Core.Immutable`
  property annotation for immutables. If maximal redundancy is wanted, the set's
  `UpdateRestrictions/NonUpdatableProperties` could *also* list them — proposed out of scope
  to avoid duplicate signals, but easy to add.
