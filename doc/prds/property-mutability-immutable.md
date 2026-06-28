# PRD: Immutable (create-only) properties + the `mutability:` foundation

> **Part A of 3** — see [`property-mutability-constraints.md`](property-mutability-constraints.md)
> for the umbrella overview. This PRD lands the `mutability:` keyword and the `:immutable`
> state. Part B adds `:non_insertable`; Part C reworks `$oas2` into per-operation bodies.

## Summary

Introduce a per-property `mutability:` keyword and its first non-trivial value, `:immutable`
(`Org.OData.Core.V1.Immutable`): a property a client may set **on create** but never change
**on update**. This PRD also establishes the keyword/enum foundation the later parts build on,
and keeps the existing `computed:` flag working as an alias.

## Goal / Problem

Today a property is either fully writable or `computed: true` (read-only — excluded from both
create and update input). There is no way to say "settable once, at creation, then frozen" —
an external reference id, an owner, an account number. A consumer must hand-roll the guard
inside `update` and gets no help in the generated contracts. OData has a dedicated term for
this, `Core.Immutable`; this PRD surfaces it through the DSL.

It also lays the **foundation** every later mutability state needs: a single `mutability:`
axis (so we are not adding one boolean keyword per state), declaration-time validation, and
backwards-compatible aliasing of today's `computed:`.

## What it enables

- *As a gem consumer, I can declare* `property 'account_number', String, mutability: :immutable`
  *so the field is accepted on create, silently ignored on update, and advertised as immutable
  in `$metadata` and the MCP update tool.*
- *As a gem consumer, my existing `computed: true` / `property_ref` declarations keep working
  unchanged* — `computed:` is now an alias on the new axis.

Scope limit: this part does **not** change `$oas2` (see Part C). Until Part C lands, an
`:immutable` property still appears in the shared `post`/`patch` request body as writable —
runtime enforcement on update is the guarantee; the Swagger contract catches up in Part C.

## External API

### The `mutability:` keyword (foundation)

A new keyword on `property` and `property_ref`. In **this part** it accepts three values;
Part B adds `:non_insertable`.

| `mutability:` | Settable on create | Settable on update | Read response | OData term |
|---|:---:|:---:|:---:|---|
| `:read_write` (**default**) | ✅ | ✅ | ✅ | *(none)* |
| `:immutable` | ✅ | ❌ | ✅ | `Core.Immutable` |
| `:computed` | ❌ | ❌ | ✅ | `Core.Computed` |

- Default is `:read_write`, matching today's default.
- **`computed: true` is retained as a backwards-compatible alias for `mutability: :computed`**
  (same word — the boolean keyword and the enum value name match); `computed: false` aliases
  `:read_write`. Existing schemas keep working unchanged.
- **`property_ref` (keys) default to `mutability: :computed`** — exactly today's "keys are
  computed by default." Opt back in with `property_ref 'id', String, mutability: :read_write`
  (equivalently `computed: false`).

### Class DSL (`OdataDuty::EntityType`)

```ruby
class OrderEntity < OdataDuty::EntityType
  property_ref 'id', String                                            # key: :computed default
  property 'account_number', String, nullable: false, mutability: :immutable  # set on create
  property 'created_at', DateTime, mutability: :computed               # server-assigned
  property 'note', String                                              # :read_write (default)
end
```

### Builder DSL (`OdataDuty::SchemaBuilder`)

```ruby
order_entity = s.add_entity_type(name: 'Order') do |et|
  et.property_ref 'id', String
  et.property 'account_number', String, nullable: false, mutability: :immutable
  et.property 'created_at', DateTime, mutability: :computed
  et.property 'note', String
end
```

### Hook contract

No new hooks. `create(input)` / `update(id, input)` keep their signatures; what changes is
which fields carry a value:

- Inside `update(id, input)`, an `:immutable` property reads back as `nil` regardless of the
  request body (over and above the existing partial-merge rule).
- Inside `create(input)`, an `:immutable` property is coerced and present as normal.

## Behavior & expected I/O

### Typed input — immutable is dropped on update, silently

Consistent with how `computed:` behaves on create today, a value the client is not allowed to
set is **silently dropped** — no error, no `InvalidType` even for a wrong-typed value; the
typed input reads it back as `nil`.

`POST /Orders` with `{ "account_number": "A-100", "note": "x" }` — inside `create`:

```ruby
input.account_number  # => "A-100"  (:immutable — settable on create)
input.note            # => "x"      (:read_write)
input.created_at      # => nil       (:computed — ignored on create)
```

`PATCH /Orders('1')` with `{ "account_number": "A-999", "note": "done" }` — inside `update`:

```ruby
input.account_number  # => nil       (:immutable — frozen on update, ignored)
input.note            # => "done"    (:read_write)
```

Read responses (`collection`, `individual`, create/update response bodies) are **unchanged**:
every property renders through the entity mapper exactly as today.

### `$metadata` (EDMX)

- `:immutable` → `Org.OData.Core.V1.Immutable` on the `<Property>`:

```xml
<Property Name="account_number" Nullable="false" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />
</Property>
```

- `:computed` → `Org.OData.Core.V1.Computed` (unchanged from today).
- `:read_write` → no annotation (unchanged).

The `Core` vocabulary is already referenced at the top of the metadata document, so no new
reference is needed.

### MCP

The `update_<Set>` tool's `inputSchema` now excludes `:immutable` properties (in addition to
the `:computed` ones it already excludes) — an immutable field cannot be sent on update. The
`create_<Set>` tool **includes** `:immutable` properties (settable on create):

```jsonc
// update tool — account_number (:immutable) and created_at (:computed) are absent
{
  "name": "update_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":   { "type": "string", "readOnly": true },
      "note": { "type": "string" }
    },
    "required": ["id"]
  }
}
```

```jsonc
// create tool — account_number (:immutable) present; created_at/id (:computed) absent
{
  "name": "create_Order",
  "inputSchema": {
    "type": "object",
    "properties": {
      "account_number": { "type": "string" },
      "note":           { "type": "string" }
    },
    "required": ["account_number"]
  }
}
```

### `$oas2` — unchanged in this part

`$oas2` is **not** modified here. The `post`/`patch` bodies keep referencing the shared
`#/definitions/<Entity>` as today, and `:computed` keeps its existing `readOnly: true`. This
means an `:immutable` property is still advertised as writable on `patch` until Part C lands;
that is a known, documented interim gap, not a regression.

## Common error cases

- **Immutable value supplied on update → silently ignored.** No error, and no
  `OdataDuty::InvalidType` even for a wrong-typed value; reads back as `nil`. Matches today's
  `computed:` behavior.
- **Unknown `mutability:` value → declaration-time error.** A symbol outside
  `{:read_write, :immutable, :computed}` (e.g. `mutability: :frozen`) raises an `ArgumentError`
  when the schema is defined, naming the property and the bad value. (Part B widens the
  accepted set to include `:non_insertable`.)
- **Both `mutability:` and `computed:` on one property → declaration-time error.** Raises
  `ArgumentError` (they control the same axis); pick one.
- **Wrong-typed value for an allowed field → unchanged.** A value that fails coercion for a
  settable property still raises `OdataDuty::InvalidType`.

## Scope

**In scope**

- `mutability:` keyword on `property` and `property_ref` in **both** DSLs, accepting
  `:read_write`, `:immutable`, `:computed`; `computed:` retained as alias; keys default to
  `:computed`; declaration-time validation.
- `:immutable` enforcement (silent drop on update) in the typed `update` input.
- Reflection in `$metadata` (`Core.Immutable`) and the MCP `create_<Set>` / `update_<Set>`
  tool input schemas.
- Matching specs under **both** `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**`.

**Out of scope (later parts)**

- `:non_insertable` (Part B).
- The `$oas2` per-operation request-body split (Part C). No `$oas2` change here.
- State/role-dependent mutability; persistence-level enforcement; navigation properties; any
  change to read rendering.

## Documentation impact

Start **`doc/using_mutability.md`** covering the `mutability:` axis and `:immutable` (the
create/update/read matrix, `$metadata` + MCP reflection), noting `$oas2` is addressed in a
follow-up. Update **`doc/using_computed.md`** to state `computed:` is now the `:computed`
alias of `mutability:` and link to the new guide. Refresh the `## Features` index in
`CLAUDE.md` with a one-line entry pointing at the new guide.

## Open questions

- **`NonUpdatableProperties` for `:immutable`.** This PRD uses the dedicated `Core.Immutable`
  property annotation. If maximal redundancy is wanted, the set's
  `UpdateRestrictions/NonUpdatableProperties` could *also* list immutables — out of scope to
  avoid duplicate signals, but easy to add.
