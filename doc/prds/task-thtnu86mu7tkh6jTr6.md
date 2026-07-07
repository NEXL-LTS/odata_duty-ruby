# PRD: Retire the `EntitySet::Metadata` mutation-testing debt

## Summary

Remove these twenty entries from `.mutant.yml`'s `matcher: ignore:` list — the eleven
class-DSL `EntitySet::Metadata` methods and their nine builder-DSL counterparts — by pinning
the consumer-observable contracts those methods implement:

```yaml
- "OdataDuty::EntitySet::Metadata#collection"
- "OdataDuty::EntitySet::Metadata#converted_id"
- "OdataDuty::EntitySet::Metadata#create"
- "OdataDuty::EntitySet::Metadata#delete"
- "OdataDuty::EntitySet::Metadata#individual"
- "OdataDuty::EntitySet::Metadata#kind"
- "OdataDuty::EntitySet::Metadata#metadata_types"
- "OdataDuty::EntitySet::Metadata#name"
- "OdataDuty::EntitySet::Metadata#new_entity_set"
- "OdataDuty::EntitySet::Metadata#non_insertable_property_names"
- "OdataDuty::EntitySet::Metadata#update"
- "OdataDuty::SchemaBuilder::Endpoint#collection"
- "OdataDuty::SchemaBuilder::Endpoint#converted_id"
- "OdataDuty::SchemaBuilder::Endpoint#create"
- "OdataDuty::SchemaBuilder::Endpoint#delete"
- "OdataDuty::SchemaBuilder::Endpoint#extend_error"
- "OdataDuty::SchemaBuilder::Endpoint#individual"
- "OdataDuty::SchemaBuilder::Endpoint#update"
- "OdataDuty::SchemaBuilder::EntitySet#initialize"
- "OdataDuty::SchemaBuilder::EntitySet#non_insertable_property_names"
```

This is a test-quality and dead-code cleanup for gem maintainers. Externally visible changes
are documentation — the default naming conventions and the `od_context` / `object` readers
become documented contract — plus one message fix: the builder DSL's `NoImplementationError`
names the resolver class instead of interpolating an object address (see Behavior below).

## Goal / Problem

The debt ratchet (`spec/using_mutant.md`) skips ignored subjects entirely, so these twenty
methods — the glue between both DSLs and every read/write operation — currently have **no
mutation gate**. Scoped mutant runs on 2026-07-07 (entries temporarily removed) measured:

- Class DSL (`EntitySet::Metadata`, 11 subjects): **380 mutations, 48 alive, 87.36%**.
- Builder DSL (`SchemaBuilder::Endpoint` / `EntitySet`, 9 subjects): **503 mutations,
  99 alive, 80.31%**.

The 147 survivors fall into distinct groups:

| Group | Count | Why it survives |
|---|---|---|
| Error-message mutants | ~30 | Specs assert the error class but never the message text (both DSLs) |
| Context-threading mutants | ~17 | No spec observes the request context reaching write hooks or response mapping |
| Backtrace decoration (`Endpoint#extend_error`) | 45 | No spec asserts the resolver source locations added to error backtraces |
| Default-name derivation | ~7 (+3 equivalent) | No spec covers `<X>EntitySet` class names or namespaced/`Resolver`-suffixed resolver names |
| `EntitySet#initialize` defensive copying & `init_args` sentinel | 11 | Clone/freeze of `name`/`url`/`resolver` and the no-init-args default are never asserted |
| Service-document `kind` | 3 | No spec asserts `"kind": "EntitySet"` in the index document |
| `NonInsertableProperties` content | ~9 (+2 equivalent) | The `$metadata` annotation content is never asserted per DSL |
| Dead / redundant code | ~20 | Unobservable through the public API — accept the mutation |

`EntitySet::Metadata#new_entity_set` has **zero** survivors: its entry is deleted with no
other work.

## What it enables

- As a gem consumer, I can rely on the documented default name derivation: a class named
  `PeopleEntitySet` or `PeopleSet` exposes the entity set `People` (class DSL), and
  `resolver: 'Admin::PeopleResolver'` defaults the set name to `People` (builder DSL).
- As a gem consumer, when a builder-DSL `collection`/`individual` resolver raises, the error's
  backtrace starts with my resolver's method, its `od_after_init`, and the `add_entity_set`
  definition site — so failures point at my code, not gem internals.
- As a gem consumer, I can rely on the exact error messages my API clients see for missing
  entities, unimplemented operations, and malformed entity ids.
- As a gem consumer, I can read the request context (`od_context`) and the raw record
  (`object`) inside custom property methods on my `EntityType`/`ComplexType` subclasses —
  now documented, previously an undocumented `od_`-convention reader.
- As a gem maintainer, every one of these methods is mutation-gated in CI from now on.

## External API

No new API surface. The following existing behaviors become pinned (spec-verified and
documented) contracts.

### 1. Default entity-set naming (both DSLs)

The entity set's `Name` in the `EntityContainer` (and its URL segment) derives, when not
given explicitly, from the class name with the `EntitySet` or `Set` suffix stripped
(class DSL), or from the resolver's last `::`-segment with the `Resolver` suffix stripped
(builder DSL); explicit `name`/`url` declarations override either:

```ruby
class PeopleEntitySet < OdataDuty::EntitySet   # => entity set "People"
  entity_type PersonEntity
  def collection = []
end

class PeopleSet < OdataDuty::EntitySet          # => entity set "People" (same)
  entity_type PersonEntity
  def collection = []
end
```

```ruby
OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                               base_path: '/api') do |s|
  # no name: — derives "People" from 'Admin::PeopleResolver'
  s.add_entity_set(entity_type: person, resolver: 'Admin::PeopleResolver')
end
```

### 1b. Resolver-error backtrace decoration (builder DSL only)

When a builder-DSL `collection` or `individual` call raises any `StandardError`, the error
propagates with its backtrace prefixed — in order — by the resolver's own method, the
resolver's `od_after_init` (when defined), and the `add_entity_set` call site, each as a
`path:line` string. This is a coined diagnostics behavior (no OData term applies): it exists
so a failing resolver points at consumer code first.

### 2. Request context in property methods (both DSLs)

Custom property methods defined on an `EntityType`/`ComplexType` subclass run during response
mapping (collection, individual, and the entity payload returned by create/update). Inside
them, `object` is the record being rendered and `od_context` is the request context:

```ruby
class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'profile_url', String

  def profile_url
    od_context.od_full_url("Profiles('#{object.id}')")
  end
end
```

The same two readers work in a `SchemaBuilder` schema via `et.property ... method: ->(obj) { }`
lambdas' class-DSL equivalent; the builder DSL shares the mapping pipeline, so mirrored specs
cover both trees.

### 3. Resolver context in write hooks (both DSLs)

The `context` reader on an `EntitySet` (class DSL) or `SetResolver` (builder DSL) is live
inside `create`, `update`, and `delete` — already described in `doc/using_context.md`, now
spec-pinned:

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def create(input)
    PERSON_REPO.insert(name: input.name, created_by: context.current_user_id)
  end
end
```

## Behavior & expected I/O

### Service (index) document

Every entity set entry carries the OData v4 service-document `kind` member with the value
`EntitySet`:

```json
{
  "@odata.context": "http://localhost/api/$metadata",
  "value": [
    { "name": "People", "kind": "EntitySet", "url": "People" }
  ]
}
```

### `$metadata` — `Capabilities.InsertRestrictions/NonInsertableProperties`

For a class-DSL entity type with `property 'legacy_code', String, mutability: :non_insertable`,
the set's annotation renders each property as an exact `PropertyPath` (vocabulary:
`Org.OData.Capabilities.V1.InsertRestrictions`, already documented in
`doc/using_mutability.md`):

```xml
<Annotation Term="Capabilities.InsertRestrictions">
  <Record>
    <PropertyValue Property="NonInsertableProperties">
      <Collection>
        <PropertyPath>legacy_code</PropertyPath>
      </Collection>
    </PropertyValue>
  </Record>
</Annotation>
```

### Pinned error messages

| Request | Error | Message |
|---|---|---|
| GET collection, resolver lacks `collection` | `NoImplementationError` | `collection not implemented for <Implementer>` |
| GET `Set(id)`, resolver lacks `individual` | `NoImplementationError` | `individual not implemented for <Implementer>` |
| GET/PATCH/DELETE `Set(id)`, no such entity | `ResourceNotFoundError` | `No such entity <id>` |
| GET/PATCH/DELETE `Set(id)`, id fails key coercion | `InvalidPropertyReferenceValue` | `Invalid individual id : <underlying reason>` |

`<Implementer>` is the class that should implement the method: the `EntitySet` subclass in
the class DSL (`PeopleSet`), the resolver class in the builder DSL (`PeopleResolver`). The
class DSL already renders this. The builder DSL currently interpolates the
`SchemaBuilder::EntitySet` object itself, producing an unstable
`#<OdataDuty::SchemaBuilder::EntitySet:0x...>` — the **one message change in this PRD**: it
must name the resolver class instead, matching the existing
`$top not implemented for <Resolver>` convention already pinned in the builder specs.

## Common error cases

The table above is exhaustive for this PRD — no new errors are introduced; the existing ones
gain message-level verification. All are raised through the existing public entry points
(`Schema.execute` / `.create` / `.update` / `.delete` and their builder-DSL equivalents).

## Resolution guide per surviving-mutation group (for /build)

Kill through the public API (option 2 of `spec/using_mutant.md`) unless marked **accept**.
The mirrored spec trees mean most kills land once per DSL — the builder `Endpoint`
duplicates the class-DSL logic almost line-for-line, including identical error messages.

- **Error-message mutants** (both DSLs: `#collection`, `#individual`, `#delete`, `#update`,
  `#converted_id`) — specs assert the full message text per the table above.
- **`obj_to_hash(result, nil)`** (both DSLs: `#collection`, `#individual`, `#create`,
  `#update`) — specs where a property method reads `od_context` observably (e.g. embeds
  `od_full_url`) on each of the four read paths.
- **Write-hook context** (class DSL `entity_set.new(context: nil)`; builder
  `new_entity_set(context: nil)`) — specs where the `create`/`update`/`delete` hook reads
  `context` and the resulting record reflects it.
- **Name derivation** — class DSL: a spec class named `<X>EntitySet` asserting the derived
  name in the index document and `$metadata`. Builder DSL: a namespaced resolver string
  (`'Admin::PeopleResolver'`, no `name:`) asserting the derived name `People` — this kills
  the `split('::')` and `sub(/Resolver$/)` mutants on `SchemaBuilder::EntitySet#initialize`.
- **`#kind`** (3) — assert `"kind": "EntitySet"` in the index document.
- **`non_insertable_property_names`** (both DSLs) — `$metadata` specs asserting the exact
  `<PropertyPath>` entries, one per DSL tree.
- **`Endpoint#extend_error`** (45) — specs that raise from a builder resolver's
  `collection`/`individual` and assert the decorated backtrace per External API §1b: the
  three prefixed `path:line` entries, their order, and the guard behavior (no
  `od_after_init` entry when the resolver doesn't define it). The `raise(err)` → `raise`
  mutant is equivalent (inside the rescue, `$!` is the same exception) — accept.
- **`SchemaBuilder::EntitySet#initialize` clone/freeze** — kill what's observable through
  the readers (`name`/`url`/`resolver` return frozen strings; mutating the caller's
  `resolver`/`name`/`url` strings after `add_entity_set` doesn't change the schema); accept
  any copy that turns out unobservable rather than testing internals.
- **`init_args: :_od_none_` sentinel** — a spec per `doc/using_init_args.md` showing a
  resolver whose `od_after_init` takes no arguments works when `add_entity_set` is called
  without `init_args:` (a `nil` default would pass an unexpected argument).
- **Accept — dead/redundant code** (verify with `bundle exec rake` after each):
  - `#name`: `gsub` → `sub` on both `\z`-anchored suffixes (matches
    `ComplexType::Metadata#name`, which already uses `sub`).
  - `#delete`: drop the trailing `result` — the return value is never observed (the REST
    response body is the `@odata.context`-only acknowledgement either way).
  - `#metadata_types`: drop `.uniq` (the schema-level `metadata_types` already uniqs) and use
    the `entity_type` reader instead of `entity_set.entity_type`.
  - `#non_insertable_property_names`: `entity_type.properties` and
    `entity_type.__metadata.properties` are the same collection — use the simpler form.
- **Likely equivalent — /build judgment** (each appears in both DSLs where the code is
  duplicated):
  - `converted_id(id, nil)` / `convert(id, nil)`: no key-eligible type reads the context
    during coercion, so the argument is unobservable today.
  - `operation: :create` vs `operation: nil` (`#create`): the input wrapper only branches on
    `== :update`. Becomes killable if the wrapper rejects unknown operation values
    (an internal call for /build).
  - `"#{e.message}"` vs `"#{e}"` (`#converted_id`): equivalent — exception interpolation
    calls `to_s`, which returns the message.
  - `/Resolver$/` vs `/Resolver\z/` (`SchemaBuilder::EntitySet#initialize`): differ only for
    resolver names containing newlines — accept `\z` (the stricter anchor).
  - `raise(err)` vs `raise` (`Endpoint#extend_error`): equivalent inside the rescue.
- **`EntitySet::Metadata#new_entity_set`**: no survivors — just delete the ignore entry.

## Scope

**In:**

- Delete all twenty entries listed in the Summary from `.mutant.yml` — the eleven
  `EntitySet::Metadata#*` and the nine `SchemaBuilder::Endpoint#*` /
  `SchemaBuilder::EntitySet#*` counterparts. All twenty subjects must finish survivor-free
  (killed or accepted); none stays on the ignore list.
- Mirrored specs in **both** trees: `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**`.
- Accept-mutation simplifications in `lib/odata_duty.rb` and
  `lib/odata_duty/schema_builder/*` listed above.
- Document `od_context`/`object`, both naming conventions, and the backtrace decoration
  (see Documentation impact).
- Gemspec patch version bump in the same change as the `lib/` edits.

**Out:**

- Every other `.mutant.yml` entry.
- Any change to error classes, response shapes, or MCP tool/resource output; message wording
  changes beyond the single builder-DSL `NoImplementationError` fix above.
- New DSL surface of any kind.

## Documentation impact

- **Extend `doc/using_context.md`** — a section on reading the request context inside entity
  type property methods (`od_context`, `object`), mirroring the External API snippet above.
- **README** — note both default naming conventions where each DSL is introduced:
  `<X>EntitySet`/`<X>Set` → `<X>` (class DSL) and `<Namespace>::<X>Resolver` → `<X>`
  (builder DSL).
- The backtrace decoration (§1b) is pinned by its specs; a short mention can join the
  builder-DSL section of the README, but no dedicated guide is warranted.
- No new guide; `doc/using_mutability.md`, `doc/using_init_args.md`, and
  `doc/using_create_update_and_delete.md` already describe the annotations, init-args, and
  errors whose content the new specs pin.

## Open questions

None blocking. The three "likely equivalent" groups above are left to /build's judgment per
`spec/using_mutant.md`: prefer accepting the mutation when the code is genuinely redundant;
never test internals to force a kill.