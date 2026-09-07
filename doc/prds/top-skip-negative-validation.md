# Fix: Reject invalid `$top`/`$skip` values

## Summary

`$top` and `$skip` are OData v4 query options (spec §11.2.5.3 `$skip`, §11.2.5.4 `$top`) whose
values must be non-negative integers. OdataDuty currently passes the raw query-string value
straight through to the consumer's `od_top`/`od_skip` hook with no validation, so a malformed
value (negative, non-numeric, or otherwise not a base-10 integer) silently produces
implementation-defined — often wrong — behavior instead of a clear error.

## Goal / Problem

**Current behavior:** `Executor#apply_top`/`#apply_skip` (`lib/odata_duty/executor.rb`) only check
whether the entity set implements `od_top`/`od_skip`; if so, they call it with whatever string
came in on the query string, unexamined:

```ruby
def apply_top(set_builder, top)
  if !set_builder.respond_to?(:od_top) && top
    raise NoImplementationError, "$top not implemented for #{set_builder.class}"
  end

  set_builder.od_top(top) if top
end
```

A request like `GET /People?$top=-5` reaches the consumer's `od_top('-5')` unchanged. A typical
hook implementation (as shown in `spec/odata_duty/entity_set/collection_spec.rb`) does
`@records[0..(top.to_i - 1)]`, so `'-5'.to_i - 1` is `-6`, and `@records[0..-6]` silently returns
some other slice of the collection instead of raising — the client gets a `200 OK` with confusing
data instead of a `400 Bad Request` explaining what was wrong with the request. The same applies
to non-numeric values (`$top=abc` becomes `0` via `.to_i`) and alternate-base-looking values
(`$top=010`, which a naive `Integer('010')` would misread as octal `8`).

**Expected behavior:** OdataDuty validates `$top`/`$skip` itself, before any hook runs, and raises
a clear `InvalidQueryOptionError` for any value that is not a valid non-negative base-10 integer.
Consumers never see a malformed value in `od_top`/`od_skip`.

## What it enables

- As a gem consumer, when a client sends `$top=-5`, `$skip=-1`, `$top=abc`, or `$top=1.5`, my
  service returns a `400 Bad Request` with a descriptive message instead of running my `od_top`/
  `od_skip` hook with garbage input.
- As a gem consumer, I can trust that any value my `od_top`/`od_skip` hook receives is already a
  valid non-negative base-10 integer string — no need to re-validate it myself.
- As a gem consumer, `$top=0` and `$skip=0` continue to work exactly as today (they are valid per
  the OData spec: "return zero entities" / "skip nothing", distinct from omitting the option).
- **Scope limit:** this only validates the *syntax* of the value (is it a non-negative base-10
  integer). It does not add any new semantic behavior, upper bound, or default — a very large
  `$top` (e.g. `$top=999999999`) is unchanged and still passed through as-is.

## External API

This is a validation fix inside the existing `$top`/`$skip` query-option handling — there is no
new DSL declaration, hook, or query option. It applies uniformly to both the class-based DSL
(`OdataDuty::EntitySet`) and the builder DSL (`OdataDuty::SetResolver`), since both share the same
`Executor`. No consumer code changes are required; existing `od_top`/`od_skip` implementations
keep the same method signature and continue to receive a string.

```ruby
# Class DSL — unchanged signature, now only ever called with a validated value
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_top(top)
    @records = @records.first(top.to_i)
  end

  def od_skip(skip)
    @records = @records.drop(skip.to_i)
  end
end
```

```ruby
# Builder DSL — same hooks, same validation, on a SetResolver
class PeopleResolver < OdataDuty::SetResolver
  def od_top(top)
    @records = @records.first(top.to_i)
  end

  def od_skip(skip)
    @records = @records.drop(skip.to_i)
  end
end
```

**Validation contract:**

- Applies to the raw `$top` and `$skip` query-option string, before `od_top`/`od_skip` support is
  checked and before either hook is invoked.
- A value is valid if and only if it is parseable as a base-10 integer (`Integer(value, 10)`,
  disallowing `0x`/`0o`/`0b` prefixes and octal-by-leading-zero misreads — `'010'` is decimal `10`,
  not octal `8`) and the resulting integer is `>= 0`.
- `nil`/absent `$top` or `$skip` (the option wasn't supplied) is unaffected — no validation runs
  and no hook is called, exactly as today.
- On an invalid value, OdataDuty raises `InvalidQueryOptionError` immediately — `od_top`/`od_skip`
  (and the `NoImplementationError` check for entity sets that don't implement them) are never
  reached for that request.

## Behavior & expected I/O

**Before (current behavior):**

```
GET /People?$top=-5
```
→ `200 OK`, calls `od_top('-5')`, response body depends on the consumer's own `.to_i` handling of
a negative slice — typically wrong, not an error.

**After (expected behavior):**

```
GET /People?$top=-5
```
→ raises `OdataDuty::InvalidQueryOptionError`, `"'$top' must be a non-negative integer, got '-5'"`
(translated by the host framework into a `400 Bad Request`, same as any other `InvalidQueryOptionError`
today, e.g. from `$select`).

```
GET /People?$skip=abc
```
→ raises `OdataDuty::InvalidQueryOptionError`, `"'$skip' must be a non-negative integer, got 'abc'"`

```
GET /People?$top=1.5
```
→ raises `OdataDuty::InvalidQueryOptionError`, `"'$top' must be a non-negative integer, got '1.5'"`

```
GET /People?$top=010
```
→ valid: parsed strictly as base-10, so `top` is `10` (not misread as octal `8`); `od_top('010')`
is called exactly as today (this fix only rejects invalid values — it does not change what string
is handed to the hook for an already-valid one).

```
GET /People?$top=0
```
→ valid, unchanged: `od_top('0')` is called; a consumer's hook implementation decides what
"top 0" returns (typically an empty `value` array).

```
GET /People?$top=25&$skip=0
```
→ valid, unchanged: both hooks are called with their respective values.

This validation is purely a request-time check — it has no effect on `$metadata` EDMX,
`$oas2`/Swagger JSON, or the MCP tool schemas. `$top`/`$skip` are already typed as OData
`Edm.Int32` / OAS2 `integer` / MCP `integer` in those outputs; this fix makes the runtime request
handling match what those outputs already advertise.

## Common error cases

- **Negative value:** `$top=-1` or `$skip=-1` → `InvalidQueryOptionError`,
  `"'$top' must be a non-negative integer, got '-1'"` (or `'$skip'`, respectively).
- **Non-numeric value:** `$top=abc` → `InvalidQueryOptionError`,
  `"'$top' must be a non-negative integer, got 'abc'"`.
- **Non-integer numeric value:** `$top=1.5` → `InvalidQueryOptionError`,
  `"'$top' must be a non-negative integer, got '1.5'"`.
- **Empty value:** `$top=` (empty string) → `InvalidQueryOptionError`,
  `"'$top' must be a non-negative integer, got ''"`.
- **Not implemented:** as today, if the entity set doesn't implement `od_top`/`od_skip`, a *valid*
  `$top`/`$skip` still raises `NoImplementationError` (`"$top not implemented for #{set_builder.class}"`).
  This is unchanged by this fix — the new check runs first and only rejects malformed values;
  well-formed values on an unsupported entity set still hit the existing `NoImplementationError`
  path.

## Scope

**In scope:**
- Validating the `$top` and `$skip` query-option values before dispatch, for both `EntitySet` and
  `SetResolver`.
- Raising `InvalidQueryOptionError` for negative, non-numeric, non-base-10, or otherwise
  malformed values.
- Leaving `$top=0`/`$skip=0` and any valid non-negative base-10 integer value unaffected.

**Out of scope:**
- Any upper bound / max-page-size enforcement on `$top`.
- Changing the type handed to `od_top`/`od_skip` (still a `String`, as today — consumers still
  call `.to_i` or equivalent themselves).
- `$skiptoken` validation (opaque token, not a numeric query option — unaffected).
- Any change to `$metadata`, `$oas2`, or MCP output shapes.

## Documentation impact

Add a new guide, `doc/using_paging.md`, covering `$top`, `$skip`, `$skiptoken`, and
`@odata.nextLink` (`od_next_link_skiptoken`) together — these currently have no dedicated guide
(only a one-line mention in `doc/odata_crash_course.md` and usage shown solely in specs). Include
this validation behavior and its error cases in that guide, in the same style as
`doc/using_filter.md` and `doc/using_select.md`.

Per `doc/conventions/doc-guides.md` (one guide per feature, linked from the `AGENTS.md` index):
update the existing `AGENTS.md` **Paging** bullet (currently guide-less) to link to the new
`doc/using_paging.md`, e.g. `... via \`od_next_link_skiptoken\`; \`$top\`/\`$skip\` reject
negative or malformed values — \`doc/using_paging.md\`.` No `README.md` example currently
demonstrates `$top`/`$skip`, so no README change is needed.
