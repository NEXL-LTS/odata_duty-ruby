# PRD: Non-insertable (update-only) properties

> **Part B of 3** — see [`property-mutability-constraints.md`](property-mutability-constraints.md)
> for the umbrella overview. Builds on Part A
> ([`property-mutability-immutable.md`](property-mutability-immutable.md)), which established
> the `mutability:` keyword. Part C reworks `$oas2` into per-operation bodies.

## Summary

Add a fourth `mutability:` value, `:non_insertable`: a property a client may **not** set on
create but **may** set on update. It maps to
`Org.OData.Capabilities.V1.InsertRestrictions/NonInsertableProperties` and completes the
write-constraint axis begun in Part A.

## Goal / Problem

Some fields do not exist at creation time and are only ever assigned later — a lifecycle
`status`, a `closed_at`, a `verified_by`. After Part A a consumer can express "create-only"
(`:immutable`) and "never" (`:computed`), but not "update-only." This PRD adds it, reusing the
keyword, validation, alias, and silent-drop semantics Part A built.

## What it enables

- *As a gem consumer, I can declare* `property 'status', String, mutability: :non_insertable`
  *so the field is silently ignored on create, accepted on PATCH, and advertised as
  insert-restricted in `$metadata` and the MCP create tool.*

Scope limit: this part does **not** change `$oas2` (see Part C). Until Part C lands, a
`:non_insertable` property still appears in the shared `post` request body as writable —
runtime enforcement on create is the guarantee; the Swagger contract catches up in Part C.

## External API

`:non_insertable` joins the `mutability:` axis from Part A. The accepted set becomes the full
four values:

| `mutability:` | Settable on create | Settable on update | OData term |
|---|:---:|:---:|---|
| `:read_write` (default) | ✅ | ✅ | *(none)* |
| `:immutable` | ✅ | ❌ | `Core.Immutable` |
| `:non_insertable` | ❌ | ✅ | `Capabilities.InsertRestrictions/NonInsertableProperties` |
| `:computed` | ❌ | ❌ | `Core.Computed` |

### Class DSL

```ruby
class OrderEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'status', String, mutability: :non_insertable   # not on create, set on update
  property 'note',   String                                # :read_write
end
```

### Builder DSL

```ruby
order_entity = s.add_entity_type(name: 'Order') do |et|
  et.property_ref 'id', String
  et.property 'status', String, mutability: :non_insertable
  et.property 'note',   String
end
```

### Hook contract

No new hooks. Inside `create(input)`, a `:non_insertable` property reads back as `nil`
regardless of the request body; inside `update(id, input)`, it is coerced and present as
normal.

## Behavior & expected I/O

### Typed input — non-insertable is dropped on create, silently

`POST /Orders` with `{ "status": "open", "note": "x" }` — inside `create`:

```ruby
input.status  # => nil   (:non_insertable — ignored on create)
input.note    # => "x"    (:read_write)
```

`PATCH /Orders('1')` with `{ "status": "closed" }` — inside `update`:

```ruby
input.status  # => "closed"  (:non_insertable — settable on update)
```

No error and no `InvalidType` for a value sent on create — it is silently dropped, matching
the rest of the axis. Read responses are unchanged.

### `$metadata` (EDMX)

A `:non_insertable` property is added to the entity set's `Capabilities.InsertRestrictions`
annotation as a `NonInsertableProperties` collection entry. This composes with the existing
set-level `Insertable: false` annotation (emitted when there is no `create`):

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

The `Capabilities` vocabulary is already referenced at the top of the metadata document.

### MCP

The `create_<Set>` tool's `inputSchema` now excludes `:non_insertable` properties (in addition
to the `:computed` ones it already excludes). The `update_<Set>` tool **includes** them:

```jsonc
// create tool — status (:non_insertable) is absent
{
  "name": "create_Order",
  "inputSchema": {
    "type": "object",
    "properties": { "note": { "type": "string" } },
    "required": []
  }
}
```

```jsonc
// update tool — status (:non_insertable) is present
{
  "name": "update_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":     { "type": "string", "readOnly": true },
      "status": { "type": "string" },
      "note":   { "type": "string" }
    },
    "required": ["id"]
  }
}
```

### `$oas2` — unchanged in this part

`$oas2` is **not** modified here (see Part C). The `post` body keeps referencing the shared
`#/definitions/<Entity>`, so a `:non_insertable` property is still advertised as writable on
`post` until Part C lands — a known, documented interim gap.

## Common error cases

- **Non-insertable value supplied on create → silently ignored.** No error, no
  `OdataDuty::InvalidType` even for a wrong-typed value; reads back as `nil`.
- **`mutability: :non_insertable` is now accepted.** The declaration-time validation from
  Part A is widened to include `:non_insertable`; the rejected-symbol error message lists all
  four valid values.
- All other error cases are unchanged from Part A (`mutability:`+`computed:` conflict, wrong
  type for an allowed field, unknown property access).

## Scope

**In scope**

- Add `:non_insertable` to the accepted `mutability:` values (both DSLs), updating the
  declaration-time validation.
- `:non_insertable` enforcement (silent drop on create) in the typed `create` input.
- Reflection in `$metadata` (`InsertRestrictions/NonInsertableProperties`) and the MCP
  `create_<Set>` / `update_<Set>` tool input schemas.
- Matching specs under **both** `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**`.

**Out of scope**

- The `$oas2` per-operation request-body split (Part C). No `$oas2` change here.
- Everything Part A already covered, and the umbrella's out-of-scope list.

## Documentation impact

Extend **`doc/using_mutability.md`** (created in Part A) with the `:non_insertable` row and its
create/update/`$metadata`/MCP behavior. No new guide.

## Open questions

None beyond the umbrella's.
