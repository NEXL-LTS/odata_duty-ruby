# PRD: Request context & typed-input contracts (mutation-ratchet burn-down)

> Burns down 7 `.mutant.yml` ratchet entries: `ContextWrapper#initialize` / `#od_full_url` and
> `CreateComplexTypeHashWrapper#initialize` / `#__load` / `#__wrap` / `#method_missing` /
> `#respond_to_missing?` — 42 surviving mutations total.

## Summary

Pin down two consumer-facing surfaces that today have surviving mutations because they are
untested and (partly) undocumented: the **request context object** handed to resolver hooks, and
the **typed input object** handed to `create`/`update` — including `mutability:` enforcement on
*nested* complex-type values. Deliverables: documentation-style specs in both DSL trees, a new
`doc/using_context.md` guide, removal of the 7 ratchet entries, and simplification of code whose
mutants have no observable behavior difference (per `spec/using_mutant.md`).

## Goal / Problem

These 7 entries guard 42 alive mutations. Diagnosis groups them into:

1. **Untested consumer contracts** — context delegation, `od_full_url`, `query_options`
   normalization, nested-input mutability, input error messages. These need specs (and docs).
2. **Equivalent mutants** — unobservable internal branches (an identity split/rejoin,
   redundant `.to_sym` on already-symbol names, dead keyword defaults, a no-op guard, an
   unobservable rescue path, an unused coercion argument). These are resolved by simplifying
   the code with no external behavior change.

When done, `bundle exec mutant run 'OdataDuty::ContextWrapper*'
'OdataDuty::CreateComplexTypeHashWrapper*'` reports 100% with the entries deleted.

## What it enables

- *As a gem consumer, I can call my own methods on `context`* inside `od_after_init`,
  `collection`, `create`, etc. — the framework's context **delegates** to the `context:` object
  I passed to `schema.execute` / `.create` / `.update` / `.delete` (e.g. a Rails controller).
- *As a gem consumer, I can build absolute service URLs* with
  `context.od_full_url(path, anchor:, **query_params)` — the same helper the framework uses for
  the `@odata.context` and `@odata.nextLink` control information (OData JSON Format §4.6).
- *As a gem consumer, I can pass any `#to_h`-able hash-like object* (e.g. Rails params) as
  `query_options:`; `context.query_options` always reads back as a plain `Hash`.
- *As a gem consumer, property `mutability:` applies to nested complex-type values* in
  create/update bodies exactly as at top level: a nested `:immutable`
  (`Org.OData.Core.V1.Immutable`) value is dropped on PATCH, a nested `:non_insertable`
  (`Capabilities.InsertRestrictions/NonInsertableProperties`) value is dropped on POST — both
  silently, matching the existing axis semantics.
- *As a gem consumer, I get a precise error* — `OdataDuty::NoSuchPropertyError` with message
  `No such property 'x'` — when reading an undefined property, or when calling a property
  accessor with arguments.

## External API

**No new API.** This PRD pins existing contracts. The context object exposes:

| Member | Contract |
|---|---|
| *(any method)* | Delegates to the caller-supplied `context:` object |
| `od_full_url(path, anchor: nil, **query_params)` | Returns a **`String`**: schema base URL + `/` + `path`, `?`-encoded `query_params` (www-form), `#anchor` fragment |
| `query_options` | The query options passed in, normalized to a plain `Hash` |
| `base_url` | The schema's base URL, no trailing `/` |
| `current` | A per-request memo `Hash`, initially empty |

`od_full_url` and `current` are **coined names** (the gem's `od_*` convention; OData has no
corresponding term for a URL-builder helper or request memo). `query_options` carries the OData
system query options under their spec spellings (`$filter`, `$top`, …).

### Class DSL

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = context.visible_people          # delegated to your context: object
  end

  def collection
    context.current['audit'] ||= context.od_full_url('People', from: 'audit')
    @records
  end
end

schema.execute('People', context: my_controller, query_options: params) # params: any #to_h-able
```

### Builder DSL

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = context.visible_people
  end

  def collection = @records
end
```

### Nested-input mutability (both DSLs)

```ruby
class AddressComplexType < OdataDuty::ComplexType
  property 'street',   String
  property 'postcode', String, mutability: :immutable       # set on create only
end

class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'address', AddressComplexType, nullable: true
end
```

```ruby
address = s.add_complex_type(name: 'Address') do |ct|
  ct.property 'street',   String
  ct.property 'postcode', String, mutability: :immutable
end
```

## Behavior & expected I/O

### `od_full_url`

With `base_path` `/odata` on host `example.org` (https):

```ruby
context.od_full_url('People')                        # => "https://example.org/odata/People"
context.od_full_url('People', top: 5)                # => "https://example.org/odata/People?top=5"
context.od_full_url('$metadata', anchor: 'People')   # => "https://example.org/odata/$metadata#People"
```

The return value is a `String` (usable in string comparison/interpolation), not a `URI`.

### `query_options` normalization

```ruby
params = RailsLikeParams.new('$top' => '1')   # any object responding to #to_h
schema.execute('People', context: ctx, query_options: params)
# inside a hook: context.query_options == { '$top' => '1' }  (a plain Hash)
```

### Nested mutability — request → typed input

`POST /People` with `{ "id": "1", "address": { "street": "Main", "postcode": "AB1" } }`:

```ruby
input.address.street    # => "Main"
input.address.postcode  # => "AB1"   (:immutable — settable on create)
```

`PATCH /People('1')` with `{ "address": { "street": "New", "postcode": "XY9" } }`:

```ruby
input.address.street    # => "New"
input.address.postcode  # => nil     (:immutable — silently dropped on update)
```

The same holds one level deeper (complex within complex) and for collections of complex values.

## Common error cases

- **Undefined property read** → `OdataDuty::NoSuchPropertyError` with message
  `No such property 'nickname'` (the message is part of the contract).
- **Property accessor called with arguments** (`input.first_name('x')`) → also
  `OdataDuty::NoSuchPropertyError`; accessors take no arguments.
- **Nested wrong-typed value on a writable property** → `OdataDuty::InvalidType`, unchanged.
- **Nested dropped value** (immutable on update / non-insertable on create) → **no error**,
  reads back as `nil` — the silent-drop semantics of `doc/using_mutability.md` extend to
  nested complex types.

## Scope

**In**

- Documentation-style specs under **both** `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**` for every contract above.
- New `doc/using_context.md`; delete the 7 `.mutant.yml` entries.
- Simplify code where a surviving mutant is behaviorally equivalent (no observable change;
  if a simplification *would* change observable behavior, stop and surface it instead).
  Version bump with the `lib/` changes.

**Out**

- Any new API surface; any change to `$metadata`, `$oas2`, or MCP output.
- Documenting `context.endpoint` (readable, but its shape stays internal).
- The remaining ~200 ratchet entries.

## Documentation impact

- **New** `doc/using_context.md` — the context object: delegation, `od_full_url`,
  `query_options`, `base_url`, `current`. Add to the CLAUDE.md Features index.
- **Extend** `doc/using_mutability.md` — a short "Nested complex types" section.
- **Extend** `doc/using_create_update_and_delete.md` — the accessor-with-args error case.