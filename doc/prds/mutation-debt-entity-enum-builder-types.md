# PRD: Retire mutation-debt for entity keys, enum types, and builder-DSL types

## Summary

Remove 26 subjects from the `matcher: ignore:` ratchet in `.mutant.yml` and re-arm the
blocking mutation gate on them, so the machinery behind **entity keys** (`property_ref` and the
`@odata.id` it produces), **enum types** (`member` / value validation), and their
**`SchemaBuilder` equivalents** is verified — not just executed — by the public-API test suite.
This is a test-quality deliverable for the gem's maintainers; it changes no consumer-facing API.

## Goal / Problem

`.mutant.yml` carries a debt ratchet (`spec/using_mutant.md`): 26 of its entries cover methods
that today have **surviving mutations** — code paths that run under 100% line/branch coverage but
whose behavior no test actually asserts. While a subject sits in `ignore:`, mutation CI skips it
entirely, so a regression to that behavior (e.g. an integer key silently rendered as a quoted
string, or an invalid enum value silently accepted) would ship green.

The consumer-observable behaviors at risk, grouped by the entries that implement them:

| Concept area | Class-based DSL entries | Builder-DSL entries |
|---|---|---|
| **Entity key & `@odata.id`** | `EntityType.__metadata`, `._defined_at_`, `.int_mapper`, `.mapper`, `.property_ref`, `.string_mapper`, `Metadata#initialize`, `#metadata_type`, `#name`, `#property_refs` | `SchemaBuilder::EntityType#int_mapper`, `#mapper`, `#property_ref`, `#string_mapper` |
| **Enum type** | `EnumMember#initialize`, `EnumType#__to_value`, `.member`, `.members`, `Metadata#name`, `#property_type` | `SchemaBuilder::EnumType#to_value` |
| **Type / container plumbing** | — | `SchemaBuilder::ComplexType#property`, `Container#initialize`, `DataType#initialize`, `DataType#scalar?` |

**Current vs. expected (test quality, not runtime):**
- *Current:* these subjects are skipped by `mutant run --since <base>`; their branches (integer-key
  vs string-key, valid-vs-invalid enum member, duplicate-property, invalid NCName) can regress
  without failing CI.
- *Expected:* all 26 entries are gone from `.mutant.yml`, and `bundle exec mutant run` reports **no
  surviving mutations** for any of them — every observable branch pinned by a public-API spec.

## What it enables

- As a gem maintainer, I can trust that changing key-URL formatting, enum validation, or the builder
  type constructors will fail CI if it breaks the documented behavior, because a mutation test
  guards each path.
- As a gem maintainer, I can keep shrinking the ratchet: this PRD removes 26 entries and adds none,
  moving the suite toward full mutation coverage.

**Scope limit:** only the 26 listed subjects are removed. The remaining `ignore:` entries stay as-is
(this PRD must not add entries, and does not claim to clean up unrelated subjects).

## External API

**No change to the consumer-facing DSL or generated output.** The DSL surface these subjects
implement is already public and stable; this deliverable only adds tests that assert its behavior
and (where a survivor proves code is redundant) simplifies `lib/` without altering observable output.

The behaviors under test are reached through the existing public surface, in both DSLs:

Class-based DSL — an entity type with a key, and an enum type:

```ruby
class ColorEnumType < OdataDuty::EnumType
  member 'Red'
  member 'Green'
end

class WidgetEntityType < OdataDuty::EntityType
  property_ref 'id', Integer            # Int64 key -> unquoted @odata.id
  property 'name', String
  property 'color', ColorEnumType, nullable: true
end
```

Builder DSL — the same shape constructed at runtime:

```ruby
OdataDuty::SchemaBuilder.build(namespace: 'My', host: 'localhost', base_path: '/api') do |s|
  color = s.add_enum_type(name: 'Color') { |e| e.member 'Red'; e.member 'Green' }
  s.add_entity_type(name: 'Widget') do |e|
    e.property_ref 'id', Integer
    e.property 'name', String
    e.property 'color', color, nullable: true
  end
  # ... add_entity_set(resolver:) wiring as in doc/using_context.md
end
```

**Contract being pinned (all already implemented; tests must assert it):**

- `property_ref name, Type` declares the entity's single key. A second `property_ref` on the same
  entity type raises (`'Multiple Property Reference not yet supported'`). The key is emitted as
  `<Key><PropertyRef Name="…"/></Key>` in `$metadata`, and is `Computed` (`Org.OData.Core.V1.Computed`)
  by default unless `mutability:`/`computed:` is given.
- The key's Edm type selects the `@odata.id` format: an `EdmInt64` key (`Integer`) yields an
  **unquoted** parenthesized id (`Widgets(1)`); any other key type yields a **quoted** id
  (`Widgets('1')`).
- An enum type emits `<EnumType Name="…"><Member Name="…"/>…</EnumType>` in `$metadata` and
  `{"type":"string","enum":[…]}` in `$oas2`; supplying a value outside its members raises
  `OdataDuty::InvalidValue`, while `nil` passes through (subject to the property's own nullability).
- Entity-type and enum-type names in the output strip a trailing `EntityType`/`Entity` and
  `EnumType`/`Enum` suffix respectively (`WidgetEntityType` → `Widget`, `ColorEnumType` → `Color`).
- Builder-DSL type constructors validate their `name` as an NCName (`InvalidNCNamesError` otherwise),
  report `scalar?` (`true` for enum, `false` for complex/entity), and reject duplicate property names
  (`PropertyAlreadyDefinedError`).

### OData terminology mapping

Every name the tests exercise is an existing OData concept; nothing is coined here.

| Behavior asserted | OData v4 term / annotation |
|---|---|
| `property_ref` key | Entity `<Key>` / `<PropertyRef>` in EDMX CSDL |
| default-`computed` key | `Org.OData.Core.V1.Computed` |
| `@odata.id` per entity | OData `@odata.id` control information (canonical URL) |
| Int64 vs other key formatting | `Edm.Int64` unquoted key literal vs quoted string key literal in the entity's id URL |
| enum type & members | EDMX `<EnumType>` / `<Member>` |
| invalid enum member | value outside the declared `Member` set (`OdataDuty::InvalidValue`) |
| invalid type/container name | XML NCName rule (`InvalidNCNamesError`) |

## Behavior & expected I/O

These are the concrete branches the new specs must observe. They are the current, correct behavior —
they read as regression pins, not new features.

**1. Integer key → unquoted `@odata.id`** (kills `int_mapper` / `mapper` int-branch, `property_refs`):

```
GET /api/Widgets
=> { "value": [ { "@odata.id": "http://localhost:3000/api/Widgets(1)", "id": 1, "name": "..." } ] }
```

**2. String key → quoted `@odata.id`** (kills `string_mapper` / `mapper` else-branch):

```
GET /api/SupportsCollection
=> { "value": [ { "@odata.id": "http://localhost:3000/api/SupportsCollection('1')", ... } ] }
```
(Matches the existing `spec/odata_duty/entity_set/collection_spec.rb` fixture — a String key.)

**3. `$metadata` key + name** (kills `Metadata#name`, `#metadata_type`, `#property_refs`, `.__metadata`):

```xml
<EntityType Name="Widget">
  <Key><PropertyRef Name="id" /></Key>
  <Property Name="id" Type="Edm.Int64" Nullable="false" />
  ...
</EntityType>
```
Assert the `Name="Widget"` suffix-stripping and the `<Key>`/`<PropertyRef>` emission via the
public `Schema.metadata_xml`.

**4. Second `property_ref` raises** (kills the guard in `property_ref`):

```ruby
class TwoKeys < OdataDuty::EntityType
  property_ref 'a', Integer
  property_ref 'b', Integer   # => RuntimeError "Multiple Property Reference not yet supported"
end
```

**5. Enum `$metadata` / `$oas2` + validation** (kills `member`, `members`, `__to_value`,
`Metadata#name`, `#property_type`, `EnumMember#initialize`, and builder `EnumType#to_value`):

```xml
<EnumType Name="Color"><Member Name="Red" /><Member Name="Green" /></EnumType>
```
```
create/POST with color: "Purple"  => OdataDuty::InvalidValue "Purple is not a valid member of ..."
create/POST with color: null       => accepted (nil passes through)
```

**6. Builder-DSL constructor guards** (kills `DataType#initialize`, `Container#initialize`,
`DataType#scalar?`, `ComplexType#property`):

```
add_entity_type(name: "9bad")            => OdataDuty::InvalidNCNamesError
property 'x'; property 'x' (same type)   => OdataDuty::PropertyAlreadyDefinedError
enum scalar? == true, complex scalar? == false  (observed via $metadata/$oas2 placement)
```

Each behavior must be asserted in **both** spec trees where the subject exists in both DSLs:
`spec/odata_duty/entity_set/**` for the class DSL and `spec/odata_duty/schema_builder/**` for the
builder DSL (see the "keep both in sync" note in `CLAUDE.md`).

## Common error cases

The specs added must exercise these existing errors (not introduce new ones):

- `OdataDuty::InvalidValue` — enum value outside declared members (`__to_value` / builder `to_value`).
- `OdataDuty::InvalidNCNamesError` — builder `DataType`/`Container` name is not a valid NCName.
- `OdataDuty::PropertyAlreadyDefinedError` — duplicate property name on a builder complex/entity type.
- `RuntimeError` `'Multiple Property Reference not yet supported'` — a second `property_ref`.

## Scope

**In:**
- Remove exactly the 26 listed subjects from `matcher: ignore:` in `.mutant.yml`.
- For each removed subject, achieve zero surviving mutations. Preferred remedy: add public-API specs
  (through `Schema.metadata_xml` / `.index_hash` / `$oas2` / `.execute` / `.create`, and the
  `SchemaBuilder` equivalents) that pin the observable behavior above. Where a survivor demonstrates
  `lib/` code is genuinely redundant, accept the mutation and simplify the source instead — per
  `spec/using_mutant.md` option 1.
- Cover **both** DSLs and **both** spec trees for any subject that exists in both.
- Land as a single deliverable: all 26 entries removed and mutation-clean together.

**Out:**
- No other `.mutant.yml` entries touched; **no new entries added**, ever.
- No new consumer-facing DSL, query option, hook, or output shape.
- No changes to `Executor`, wrappers, ERB templates, or other internals beyond an accepted-mutation
  simplification that leaves observable output identical.
- Tests must use only the public API (no `stub_const`/internal-class testing) per `AGENTS.md`.

**Verification gate:** after the change, `bundle exec mutant run` on each removed subject
(e.g. `bundle exec mutant run 'OdataDuty::EntityType.mapper'`) reports no survivors, and
`bundle exec rake` stays green (RSpec + RuboCop + 100% coverage).

## Documentation impact

No consumer-facing guide changes (behavior is unchanged). Update `spec/using_mutant.md` only if the
cleanup changes the recorded debt count/rationale; the ratchet's rules already describe this
workflow. Do **not** write a new `doc/` guide for this — it is internal test-quality work.

## Open questions

- If any subject's survivors can only be killed by asserting behavior that has no public-API
  observation point, that is a signal (per `AGENTS.md`) to question the behavior/simplify rather than
  reach into internals — flag such cases during `/build` rather than testing internals directly.
