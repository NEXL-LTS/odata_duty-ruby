# PRD: Mutation-gate the Edm scalar types (remove their `.mutant.yml` debt entries)

## Summary

Remove the ten `OdataDuty::Edm*.to_oas2` / `.to_value` entries from the `.mutant.yml` debt
ratchet by pinning the consumer-observable contracts of the five OData primitive types the gem
supports — `Edm.Int64`, `Edm.String`, `Edm.Date`, `Edm.DateTimeOffset`, `Edm.Boolean` — with
public-API specs, and by making coercion failures on create/update report the underlying reason.

The entries to remove:

```yaml
- "OdataDuty::EdmBool.to_oas2"
- "OdataDuty::EdmBool.to_value"
- "OdataDuty::EdmDate.to_oas2"
- "OdataDuty::EdmDate.to_value"
- "OdataDuty::EdmDateTimeOffset.to_oas2"
- "OdataDuty::EdmDateTimeOffset.to_value"
- "OdataDuty::EdmInt64.to_oas2"
- "OdataDuty::EdmInt64.to_value"
- "OdataDuty::EdmString.to_oas2"
- "OdataDuty::EdmString.to_value"
```

## Goal / Problem

An ignore entry means *no* mutation gate on that method. A scoped mutant run (2026-07-06,
mutant 0.16.3) shows **29 surviving mutations** across the ten subjects (coverage 88.8%). The
survivors expose two real consumer-facing gaps and two pieces of dead code:

1. **Generic 400 errors** (15 survivors): when a POST/PATCH body value fails coercion, the
   consumer sees only `The value provided for 'number' is of wrong type`. The underlying reason
   (`invalid value for Integer(): "abc"`) is discarded, so no spec can verify it — and API
   clients can't see why their value was rejected. **Expected:** the reason is included in the
   error message.
2. **Unpinned coerced-value shape** (2 survivors): nothing asserts that `Edm.Date` /
   `Edm.DateTimeOffset` coercion produces an ISO 8601 **String** (`'2021-01-01'`) rather than a
   `Date`/`DateTime` object. **Decision: the ISO 8601 String is the contract** — pin it with
   specs and clarify `doc/using_filter.md`, which currently says values are "coerced to the
   property's declared type".
3. **Dead code** (12 survivors): the `is_collection:` keyword default on each type's `$oas2`
   fragment is never used (every framework call passes it explicitly), and the `Edm.Int64` nil
   guard is unreachable (nil short-circuits before type coercion on every public path). Per
   `spec/using_mutant.md` option 1, these are resolved by *accepting the mutation* —
   behavior-preserving simplification, no observable change.

## What it enables

- As a gem consumer, when I create or update an entity with an uncoercible value, the 400 error
  tells me *why* (e.g. the malformed date), not just which field.
- As a gem consumer, I can rely on `od_filter_*` predicate values and typed create-input
  accessors handing me an ISO 8601 String for `Edm.Date`/`Edm.DateTimeOffset` properties.
- Every mutation of the five primitive types' coercion and `$oas2` output is caught by CI.

## External API

The only surface *change* is the coercion-failure message on create/update (both DSLs share it;
specs go in both trees). No new DSL keywords, hooks, or query options.

Class DSL:

```ruby
class PersonEntity < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'birth_date', Date
end

class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity
  def create(input)
    Person.create!(birth_date: input.birth_date) # input.birth_date => '2021-01-01' (ISO 8601 String)
  end
end
```

Builder DSL: identical behavior via `resolver:` + `OdataDuty::SetResolver`.

## Behavior & expected I/O

**Create with an uncoercible value — before/after:**

```
POST /People  {"birth_date": "2021-01-32"}
```

|        | `InvalidType` message (rendered as the 400 error body)               |
|--------|----------------------------------------------------------------------|
| Before | `The value provided for 'birth_date' is of wrong type`               |
| After  | `The value provided for 'birth_date' is of wrong type: invalid date` |

The appended reason is the coercion failure for each type, e.g. `invalid value for
Integer(): "abc"` (`Edm.Int64`), `undefined method 'to_str' …` (`Edm.String`), `blueblah not
boolean value` (`Edm.Boolean`). Exact reason wording follows Ruby's conversion errors; specs
assert the observable message.

**Coerced values handed to consumer hooks (pinned, unchanged):**

```
GET /People?$filter=birth_date eq 2021-01-01
```

→ `od_filter_eq('birth_date', '2021-01-01')` — an ISO 8601 String, not a `Date`.

**`$oas2` output:** unchanged; the existing fragments (`{'type' => 'integer', 'format' =>
'int64'}`, `{'type' => 'array', 'items' => …}`, etc.) are already asserted for all five types,
single and collection.

## Resolution guide per surviving mutation group (for `/build`)

- **Message mutations** (`raise InvalidValue, e.message` → `nil`/no-arg; `Edm.Boolean`'s
  interpolated message): killed by create/update specs asserting the enriched message per type,
  in both spec trees. `raise(InvalidValue, e)` is likely an equivalent mutant
  (`e.to_s == e.message`); if unkillable, accept it as the simpler form.
- **`.iso8601` removal** (`Edm.Date`, `Edm.DateTimeOffset`): killed by specs observing the
  coerced value through a public hook (e.g. a resolver asserting the filter value's class/value,
  or create echoing the coerced value).
- **`Edm.Boolean` `object.to_boolean` → `self.to_boolean`**: killed by a create spec passing a
  custom object responding to `to_boolean` (body hashes passed to `Schema.create` are plain
  Ruby values).
- **`is_collection:` default / `Edm.Int64` nil guard**: accept the mutation (required keyword;
  drop the guard). Not reachable via public API; no observable change.
- Finish by deleting the ten entries and running `bundle exec mutant run` on the ten subjects —
  zero alive.

## Common error cases

- Uncoercible POST/PATCH body value → `InvalidType` (400), message now
  `The value provided for '<name>' is of wrong type: <reason>`.
- Uncoercible `$filter` value → `InvalidFilterValue` (400), unchanged:
  `Invalid value <value> for <name>`.
- Entity data that fails rendering (e.g. a non-boolean in an `Edm.Boolean` property) →
  `InvalidValue` (server error), unchanged.

## Scope

- **In:** the ten listed `.mutant.yml` entries; specs in both `spec/odata_duty/entity_set/**`
  and `spec/odata_duty/schema_builder/**`; the enriched create/update error message; doc
  clarification; gemspec patch bump (lib changes).
- **Out:** all other ratchet entries (including adjacent `Property::SingleProp#to_value`);
  enriching the `$filter` error message; changing coerced value types; MCP error shapes.

## Documentation impact

- Extend `doc/using_create_update_and_delete.md`: the coercion-failure message now includes the
  reason.
- Clarify `doc/using_filter.md`: coerced values for `Edm.Date`/`Edm.DateTimeOffset` are ISO 8601
  Strings.