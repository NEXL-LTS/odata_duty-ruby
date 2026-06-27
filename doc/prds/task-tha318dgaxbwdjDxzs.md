# Stop masking `create` / `update` implementation errors

## Summary

When a writable entity set's `create` or `update` implementation raises a `NoMethodError`
internally, OdataDuty currently swallows it and re-raises a misleading
`NoImplementationError` ("create not implemented for …"). This PRD makes `create` and
`update` behave like `delete` already does: decide "is this operation implemented?" from the
`supports_create?` / `supports_update?` capability check, and let any `NoMethodError` thrown
*inside* the consumer's own code bubble up unchanged.

## Goal / Problem

`delete` distinguishes "the set has no `delete` method" from "the consumer's `delete` blew up"
by gating on the capability predicate first and only then calling the data method:

```ruby
# Executor#delete (today)
unless endpoint.supports_delete?
  raise NoImplementationError, "delete not implemented for #{endpoint.url}"
end
# ... calls endpoint.delete; any NoMethodError it raises propagates as-is
```

`create` and `update` do **not** do this. They call the data method and blanket-rescue
`NoMethodError`, re-labeling *every* `NoMethodError` — including bugs deep inside the
consumer's own `create`/`update` — as "not implemented":

```ruby
# Executor#create (today)
def create
  Oj.dump(endpoint.create(context: wrapped_context).merge(...), mode: :compat)
rescue NoMethodError
  raise NoImplementationError, "create not implemented for #{endpoint.url}"
end
```

**Current (wrong) behavior:** A consumer whose `create` calls `Person.creat!(...)` (typo) or
references an undefined helper sees `OdataDuty::NoImplementationError: create not implemented
for People`, with the real `NoMethodError` and its backtrace discarded. The error points at
the framework, not at the bug.

**Expected behavior:** That `NoMethodError` propagates with its original message and backtrace.
`NoImplementationError` is raised **only** when the set genuinely does not define `create` /
`update` — determined up front by `supports_create?` / `supports_update?`, never by catching a
`NoMethodError` after the fact.

## What it enables

- As a gem consumer, when I have a bug in my `create` or `update` implementation (a typo, a
  call to a method that doesn't exist, a `nil` where I expected an object), I see the actual
  `NoMethodError` from my code instead of a misleading "not implemented" message — so I can
  find and fix it.
- As a gem consumer, the diagnostic story is now uniform across all three writes (`create`,
  `update`, `delete`): "operation absent" is one error, "your code raised" is another, and the
  two are never conflated.

Scope limit: this changes only *which* error surfaces when a consumer's `create`/`update`
raises `NoMethodError`. The behavior for a set that legitimately lacks `create`/`update` is
unchanged — same `NoImplementationError`, same message.

## External API

No new DSL, hook, or query option. This is a fix to the observable error behavior of the
existing `create` / `update` operations, reached through the existing public entry points
`Schema.create` / `Schema.update` (POST / PATCH) and the MCP `create_<Set>` / `update_<Set>`
tools.

Writability is still inferred exactly as documented in
[`doc/using_create_update_and_delete.md`](../using_create_update_and_delete.md): a set is
creatable iff it defines `create`, updatable iff it defines `update`. The capability checks
already exist for both DSLs (`supports_create?` / `supports_update?`), so no consumer-facing
declaration changes.

Both DSLs are covered, because the shared GET/write executor is what changes:

```ruby
# Builder DSL (OdataDuty::SetResolver) — a buggy create
class PeopleResolver < OdataDuty::SetResolver
  def create(input)
    Person.creat!(name: input.name)   # typo: NoMethodError raised inside consumer code
  end
end
```

```ruby
# Class DSL (OdataDuty::EntitySet) — a buggy update
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def update(id, input)
    record = @records.find(id)
    record.touchh                       # typo: NoMethodError raised inside consumer code
    record
  end
end
```

## Behavior & expected I/O

### Before (current)

```ruby
schema.create("People", context: ctx, query_options: { "name" => "Alice" })
# => raises OdataDuty::NoImplementationError: create not implemented for People
#    (the real NoMethodError from `Person.creat!` is lost)

schema.update("People('1')", context: ctx, query_options: { "name" => "Alice" })
# => raises OdataDuty::NoImplementationError: update not implemented for People
#    (the real NoMethodError from `record.touchh` is lost)
```

### After (fixed)

```ruby
schema.create("People", context: ctx, query_options: { "name" => "Alice" })
# => raises NoMethodError: undefined method `creat!' for Person
#    (the consumer's real error, with its original backtrace)

schema.update("People('1')", context: ctx, query_options: { "name" => "Alice" })
# => raises NoMethodError: undefined method `touchh' for #<Person ...>
#    (the consumer's real error, with its original backtrace)
```

### Unchanged: genuinely-missing operation

For a read-only set (no `create` / no `update`), the error is identical before and after — now
produced by the capability gate rather than a rescued `NoMethodError`:

```ruby
# Set defines neither create nor update
schema.create("Countries", context: ctx, query_options: { ... })
# => raises OdataDuty::NoImplementationError: create not implemented for Countries

schema.update("Countries('1')", context: ctx, query_options: { ... })
# => raises OdataDuty::NoImplementationError: update not implemented for Countries
```

### Unchanged: successful write

A correct `create` / `update` still returns the affected entity, mapper-rendered with the
`@odata.context` anchor, exactly as documented today — no change to the success path.

### Generated contracts

No change to `$metadata`, `$oas2`, the index document, or the MCP `tools/list` shapes. Insert/
update capability is still advertised via the presence of the method
(`InsertRestrictions` / `UpdateRestrictions` annotations, `post` / `patch` operations, and the
`create_<Set>` / `update_<Set>` tools), exactly as
[`doc/using_create_update_and_delete.md`](../using_create_update_and_delete.md) describes.

## Common error cases

- **`POST` to a set without `create` / `PATCH` to a set without `update`:** raises
  `OdataDuty::NoImplementationError` with `create not implemented for <url>` /
  `update not implemented for <url>` (the set's URL, e.g. `create not implemented for People`).
  Same message as today; now produced by the `supports_create?` / `supports_update?` gate.
- **Consumer's `create` / `update` raises `NoMethodError`:** that `NoMethodError` now
  propagates unchanged (message + backtrace preserved). It is **no longer** rewritten to
  `NoImplementationError`. This is the behavioral change.
- **`PATCH` for a key that doesn't exist:** unchanged — when `update` returns falsey the
  framework raises `OdataDuty::ResourceNotFoundError` (`No such entity <id>`).
- **Invalid key in the `PATCH` URL / body that fails coercion:** unchanged —
  `OdataDuty::InvalidPropertyReferenceValue` for a bad key, `OdataDuty::InvalidType` for a
  wrong-typed body value, `OdataDuty::NoSuchPropertyError` for accessing an undefined property
  on the input object.
- **MCP `create_<Set>` / `update_<Set>` for a set lacking the capability:** unchanged — the
  tool is never listed, so `tools/call` raises `"Unknown tool: <tool>"`.

## Scope

**In:**
- `create` and `update` decide "implemented?" via the existing capability predicates
  (`supports_create?` / `supports_update?`) up front, and stop blanket-rescuing `NoMethodError`
  from the consumer's data method — mirroring `delete`.
- Applies to **both** DSLs (class-based and builder), since the shared write executor is what
  changes and both DSLs already expose `supports_create?` / `supports_update?`.
- Patch version bump in `odata_duty.gemspec` (`0.20.0` → `0.20.1`).

**Out:**
- No change to the success path, the `$metadata` / `$oas2` / index / MCP outputs, or any DSL
  declaration / hook.
- No change to `delete` (already correct) or to non-write operations (`collection`,
  `individual`, `count`).
- No change to `NoImplementationError`'s message text for a genuinely-missing operation.

## Documentation impact

Extend [`doc/using_create_update_and_delete.md`](../using_create_update_and_delete.md): in its
**Common Error Cases** section, add a note (parallel to the existing "not implemented" bullet)
clarifying that a `NoMethodError` raised *inside* a consumer's `create` / `update` propagates
unchanged and is **not** rewritten to `NoImplementationError` — so a real bug in the
implementation surfaces as the real error, consistent with `delete`. No new guide needed.

## Open questions

None. The design follows the established `delete` precedent and the predicates it relies on
already exist for both DSLs.