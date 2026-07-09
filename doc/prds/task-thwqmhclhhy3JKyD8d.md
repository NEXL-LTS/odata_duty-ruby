# Retire the `Executor` mutation-testing debt

## Summary

Remove all 24 `OdataDuty::Executor#*` entries from `.mutant.yml`'s ignore list by pinning the
request-execution contract — URL dispatch, key extraction, query-option application, response
envelopes, and error messages — as spec-asserted public behavior, exercised through
`schema.execute` / `.create` / `.update` / `.delete` in **both** DSLs. No output changes — this
is a pure pin. The externally visible changes are specs, plus any accept-mutation
simplifications inside the executor.

```yaml
- "OdataDuty::Executor#_filter"
- "OdataDuty::Executor#add_next_link"
- "OdataDuty::Executor#apply_remaining"
- "OdataDuty::Executor#apply_search"
- "OdataDuty::Executor#apply_select"
- "OdataDuty::Executor#apply_skip"
- "OdataDuty::Executor#apply_skiptoken"
- "OdataDuty::Executor#apply_top"
- "OdataDuty::Executor#assert_filter_valid_for_property"
- "OdataDuty::Executor#collection"
- "OdataDuty::Executor#create"
- "OdataDuty::Executor#delete"
- "OdataDuty::Executor#endpoint"
- "OdataDuty::Executor#execute"
- "OdataDuty::Executor#extract_value_from_brackets"
- "OdataDuty::Executor#filter_value"
- "OdataDuty::Executor#individual"
- "OdataDuty::Executor#initialize"
- "OdataDuty::Executor#prepare_builder"
- "OdataDuty::Executor#selected"
- "OdataDuty::Executor#update"
- "OdataDuty::Executor#urls"
- "OdataDuty::Executor#valid_selected"
- "OdataDuty::Executor#wrapped_context"
```

## Goal / Problem

Measured 2026-07-09 (entries temporarily removed, run scoped to `OdataDuty::Executor*`):
**32 subjects, 1474 mutations, 1357 killed, 117 alive — 92.06% coverage.** The 8 subjects not
on the ignore list (`.execute` / `.create` / `.update` / `.delete`, `#points`, `#apply_filter`,
`#apply_and_filter`, `#apply_or_filter`) finished survivor-free, as did the ignored
`#wrapped_context` — its entry deletes for free.

The root cause here is **assertion gaps, not test selection** — the opposite of the `$oas2`
retirement. No spec in the suite describes `OdataDuty::Executor`, so mutant's rspec integration
falls back to running the *entire* suite (762 tests) against every mutation; that fallback is
what already kills 92%. The 117 survivors are behaviors observable at the public API that no
spec ever asserts: error-message text, `(id)` key quote handling, `$select` whitespace
tolerance, the DELETE response envelope, `$count=true` strictness, and the
option-vs-capability gating truth table.

**Anchoring warning — do not `RSpec.describe OdataDuty::Executor`.** The moment any spec
describes that constant, mutant narrows selection for *all* `Executor` subjects to just those
specs, discarding the full-suite fallback that currently kills 1357 mutations. New specs must
keep the existing two-tree convention (`RSpec.describe OdataDuty::EntitySet, '<feature>'` /
`RSpec.describe OdataDuty::SchemaBuilder::EntitySet, '<feature>'`); the fallback then selects
them along with everything else. This also keeps the specs where they belong as public
documentation of both DSLs.

## What it enables

- As a gem consumer, the error messages my API clients receive — unknown endpoint, unknown
  property, unsupported `$filter` operation, unimplemented write operation or query option —
  are pinned, spec-asserted contract that cannot silently change.
- As a gem consumer, entity addressing by key is documented: `People('bob')`, `People("bob")`,
  and `People(1)` all resolve the same entity, and quotes are stripped only at the edges.
- As a gem consumer, `$select=first_name, last_name` (whitespace around commas) works and is
  documented; invalid and unknown property names fail with pinned messages.
- As a maintainer, the entire read/write execution path is mutation-gated; regressions in
  request handling fail CI.

## External API

**No new DSL surface.** The public entry points are the four request methods, identical in
both DSLs (class methods on a `Schema` subclass; instance methods on a built schema):

```ruby
schema.execute(url, context: ctx, query_options: opts)  # GET: collection, (key), /$count
schema.create(url, context: ctx, query_options: opts)   # POST
schema.update(url, context: ctx, query_options: opts)   # PATCH, url carries (key)
schema.delete(url, context: ctx, query_options: opts)   # DELETE, url carries (key)
```

### The pinned contract

All names below use OData v4 spelling: system query options (`$filter`, `$select`, `$search`,
`$top`, `$skip`, `$count`, `$skiptoken`) and JSON control information (`@odata.context`,
`@odata.nextLink`, `@odata.count`) per the OData JSON Format. OData string keys use single
quotes (`People('bob')`); accepting double quotes as well is a **coined** leniency of this gem
and becomes pinned contract. Error classes are the gem's existing public ones.

1. **URL dispatch** — the endpoint is resolved by exact URL match after dropping a `(...)` or
   `/$count` suffix. An unrecognized URL raises `UnknownPropertyError` with message
   `No endpoint <url> found in [<every set url>]` — the list names all registered sets.
2. **Key extraction** — the value inside `(...)` addresses the individual entity on GET,
   PATCH, and DELETE alike. One pair of surrounding double quotes, then one pair of
   surrounding single quotes, is stripped; interior quotes are preserved (`People('bob')`,
   `People("bob")`, and `People(bob)` are equivalent; `People('it''s')` yields `it''s` — the
   gem does not implement OData quote-doubling).
3. **`$select`** — comma-separated property names with surrounding whitespace stripped.
   A malformed name raises `InvalidQueryOptionError` (`The property '<p>' is not valid`); a
   well-formed but undeclared name raises `UnknownPropertyError`
   (`The property '<p>' does not exist`). Both errors carry the entity type's definition
   location as the first backtrace entry.
4. **`od_select` hook** — when the resolver defines `od_select`, it receives the selected
   property names plus the key (`property_ref`) names, deduplicated; with no `$select`, the
   full property list.
5. **Write capability gating** — `create` / `update` / `delete` on a set whose resolver lacks
   the method raises `NoImplementationError`, message `<op> not implemented for <set url>`
   (the runtime enforcement of `Capabilities.InsertRestrictions` / `UpdateRestrictions` /
   `DeleteRestrictions`, `doc/using_create_update_and_delete.md`).
6. **Query-option gating** — `$top` / `$skip` / `$skiptoken` / `$search` each raise
   `NoImplementationError`, message `<$option> not implemented for <ResolverClass>`, when
   passed to a resolver lacking the matching `od_*` hook; when the option is absent the hook
   is not called, and its absence alone never raises. Non-`$` query options are ignored.
7. **Response envelopes** — collection: `@odata.context` anchored `#<SetName>`, results under
   `value`, `@odata.count` present iff `$count=true` exactly (any other value: no count),
   `@odata.nextLink` present iff the resolver returns an `od_next_link_skiptoken`, carrying
   the original query options plus `$skiptoken`. Individual, create, update: `@odata.context`
   anchored `#<SetName>/$entity`. Delete: exactly
   `{"@odata.context": "<base url>/$metadata"}`.
8. **`$filter` errors** — filtering an undeclared property raises `UnknownPropertyError`
   (`No such property <name>`); a non-collection operation on a collection property raises
   `InvalidQueryOptionError`
   (`Cannot apply '<op>' to a collection property '<name>'.`); an operation the resolver
   implements no `od_filter_*` hook for raises `NoImplementationError`
   (`<property> <op> not supported`). Filter values are coerced with the request context
   (already partly pinned by the `$filter` date-coercion specs).

## Behavior & expected I/O

Given a `People` set whose resolver implements only `od_after_init` + `collection` +
`individual`:

```ruby
schema.execute('People', context: ctx, query_options: { '$select' => 'first_name, last_name' })
# 200 — whitespace around the comma is tolerated

schema.execute('People', context: ctx, query_options: { '$select' => 'first-name' })
# raises InvalidQueryOptionError, "The property 'first-name' is not valid"

schema.execute('People', context: ctx, query_options: { '$top' => '5' })
# raises NoImplementationError, "$top not implemented for PeopleResolver" (no od_top)

schema.execute('People', context: ctx, query_options: {})
# 200 — the absence of od_top alone never raises

schema.create('People', context: ctx, query_options: {})
# raises NoImplementationError, "create not implemented for People"

schema.execute('Nope', context: ctx, query_options: {})
# raises UnknownPropertyError, "No endpoint Nope found in [\"People\"]"
```

Key handling and the DELETE envelope, on a full-CRUD set with a `String` key:

```ruby
schema.execute(%q{People('bob')}, ...)   # same entity as People("bob") and People(bob)
schema.delete(%q{People('bob')}, context: ctx, query_options: {})
# => '{"@odata.context":"http://localhost/api/$metadata"}'
```

`$count` strictness on a resolver with `count`:

```ruby
schema.execute('People', context: ctx, query_options: { '$count' => 'true' })
# body includes "@odata.count"
schema.execute('People', context: ctx, query_options: { '$count' => '1' })
# body has no "@odata.count"
```

## Common error cases

No new errors and no message changes — these existing messages *become* pinned contract:

| Error | Message | When |
|---|---|---|
| `UnknownPropertyError` | `No endpoint <url> found in [<urls>]` | URL matches no entity set |
| `UnknownPropertyError` | `The property '<p>' does not exist` | `$select` names an undeclared property |
| `InvalidQueryOptionError` | `The property '<p>' is not valid` | `$select` names a malformed property |
| `UnknownPropertyError` | `No such property <name>` | `$filter` on an undeclared property |
| `InvalidQueryOptionError` | `Cannot apply '<op>' to a collection property '<name>'.` | non-collection `$filter` op on a collection property |
| `NoImplementationError` | `<property> <op> not supported` | no matching `od_filter_*` hook |
| `NoImplementationError` | `<create\|update\|delete> not implemented for <url>` | write op without the resolver method |
| `NoImplementationError` | `<$option> not implemented for <ResolverClass>` | `$top`/`$skip`/`$skiptoken`/`$search` without the `od_*` hook |

## Resolution guide

Per `spec/using_mutant.md`, each survivor is resolved by an accepted simplification or a
public-API spec — written twice, once per DSL tree, matching the existing near-identical
pairing. Alive counts from the 2026-07-09 baseline:

| Group | Subjects (alive) | Kill route |
|---|---|---|
| Write-gating messages | `#create` (5), `#update` (5), `#delete` (13 incl. envelope) | Assert exact `NoImplementationError` messages on a read-only set; pin the exact DELETE response JSON string |
| Endpoint resolution | `#endpoint` (2), `#urls` (6) | Schema with ≥2 sets; assert the full unknown-endpoint message including the URL list |
| Key extraction | `#extract_value_from_brackets` (12) | Same entity via `('k')` / `("k")` / bare; interior-quote preservation; expect a residue of accepted regex-anchor tightenings (`^`→`\A`, `$`→`\z`) |
| `$select` parsing | `#selected` (17), `#valid_selected` (3), `#execute` (2) | Whitespace-tolerance spec; exact invalid/unknown messages; backtrace head is the type's definition location |
| `od_select` payload | `#apply_select` (6) | Resolver capturing its `od_select` argument: full list without `$select`, selected+refs deduplicated with it |
| `$filter` guards | `#assert_filter_valid_for_property` (12), `#_filter` (6), `#filter_value` (3) | Exact messages; a collection-op filter that succeeds on a collection property; context-dependent coercion reaching the hook |
| Option gating | `#apply_search` (4), `#apply_skip` (3), `#apply_skiptoken` (3), `#apply_top` (1) | Truth-table specs: option absent + hook absent → no raise; option absent + hook present → hook not called; exact messages |
| `$count` / nextLink | `#collection` (1), `#add_next_link` (1) | `$count=true` vs other values; `@odata.nextLink` URL uses the set's URL |
| Plumbing residue | `#initialize` (4), `#apply_remaining` (4), `#individual` (3), `#prepare_builder` (1) | Case-by-case: pin (e.g. non-`$` options ignored; query options applied on individual requests) or accept the simpler form |

A small accept/equivalent residue is expected (`send`→`__send__`, slice-bound tweaks in
`apply_remaining`, `.to_str` on `base_url`). Accept case-by-case; any acceptance that changes
`lib/` lands with the specs and a gemspec patch bump.

**Verification.** The gate is `bundle exec mutant run 'OdataDuty::Executor*'` after deleting
the entries: zero alive. Because new specs may also be selected for other subjects' mutations,
finish with `bundle exec rake` (which CI runs four times) and the usual
`bundle exec mutant run --since main`.

## Scope

**In:**
- Delete all 24 `OdataDuty::Executor#*` entries from `.mutant.yml`. All subjects finish
  survivor-free (killed or accepted); none stays on the ignore list.
- New behavior-pinning specs in **both** spec trees, described under the existing
  `EntitySet` / `SchemaBuilder::EntitySet` constants (never `OdataDuty::Executor`).
- Accept-mutation simplifications inside `lib/odata_duty/executor.rb` where the tests agree,
  with a gemspec patch bump iff any `lib/` change lands.

**Out:**
- Any change to request/response behavior or error-message wording — everything stays
  byte-identical.
- Every other ignore-list entry (e.g. `OdataDuty::Filter*`, `OdataDuty::SetResolver#*`).
- OData quote-doubling (`'it''s'`) or any other key-syntax extension.

## Documentation impact

No new guide; the specs are the reference. Optionally extend `doc/using_filter.md` and
`doc/using_select.md` with one line each naming the exact error messages, matching their
existing "Common Error Cases" sections.