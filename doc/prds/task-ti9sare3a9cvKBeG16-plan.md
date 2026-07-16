# Build plan: Retire mutation-debt for entity keys, enum types, and builder-DSL types

PRD: [task-ti9sare3a9cvKBeG16.md](./task-ti9sare3a9cvKBeG16.md)

This is a test-quality deliverable. Each task removes a group of subjects from the
`matcher: ignore:` ratchet in `.mutant.yml`, then makes those subjects mutation-clean —
preferably by adding public-API specs that pin the observable behavior, or (where a survivor
proves code redundant) by accepting the mutation and simplifying `lib/`. `bundle exec rake`
(RSpec + RuboCop + 100% coverage) must stay green, and `bundle exec mutant run '<subject>'`
must report **no survivors** for every removed subject.

The PRD names 26 entries in prose but lists 25 distinct subjects in its table / in `.mutant.yml`
(lines 19–34 and 100–108). We remove exactly the 25 listed subjects; the count is noted in the PR.

Hard rules for every task: public-API tests only (no internal classes, no `stub_const`); TDD;
99-char lines, two-space indent, RuboCop metrics; keep both DSLs in sync where a subject exists
in both; run `bundle exec mutant run '<subject>'` for each removed subject and confirm no
survivors. **Never add ignore entries.**

## Tasks

- [x] **Task 1 — Class-DSL entity key & `@odata.id` + entity metadata.**
  Remove these 10 entries from `.mutant.yml`: `OdataDuty::EntityType.__metadata`,
  `.._defined_at_`, `..int_mapper`, `..mapper`, `..property_ref`, `..string_mapper`,
  `EntityType::Metadata#initialize`, `#metadata_type`, `#name`, `#property_refs`. Add public-API
  specs under `spec/odata_duty/entity_set/**` pinning: an **Integer** (`EdmInt64`) key yields an
  **unquoted** `@odata.id` (`Widgets(1)`); a **String** key yields a **quoted** id
  (`SupportsCollection('1')`); `$metadata` emits `<EntityType Name="Widget"><Key><PropertyRef
  Name="id"/></Key>…` with the `EntityType`/`Entity` suffix stripped and the key defaulting to
  `Org.OData.Core.V1.Computed`; a **second** `property_ref` raises `RuntimeError` `'Multiple
  Property Reference not yet supported'`. Reach everything through `Schema.metadata_xml`,
  `.index_hash`, and `.execute` (collection + individual). Run mutant on all 10 subjects; kill
  all survivors (add specs, or accept a mutation and simplify `lib/odata_duty/entity_type.rb`
  leaving output identical). `bundle exec rake` green. Class DSL only (builder key mappers are Task 3).

- [x] **Task 2 — Class-DSL enum type.**
  Remove these 6 entries: `OdataDuty::EnumMember#initialize`, `EnumType#__to_value`,
  `EnumType.member`, `EnumType.members`, `EnumType::Metadata#name`,
  `EnumType::Metadata#property_type`. Add public-API specs under `spec/odata_duty/entity_set/**`
  pinning: `<EnumType Name="Color"><Member Name="Red"/><Member Name="Green"/></EnumType>` in
  `$metadata` (`EnumType`/`Enum` suffix stripped); `{"type":"string","enum":["Red","Green"]}` in
  `$oas2`; a create/POST (or read) with a value **outside** the members raises
  `OdataDuty::InvalidValue` (`"Purple is not a valid member of …"`); `nil` passes through subject
  to the property's own nullability; the enum property's rendered type uses the derived name.
  Reach through `Schema.metadata_xml`, the `$oas2` doc, `.create`/`.execute`. Kill all survivors
  on the 6 subjects. `bundle exec rake` green. Class DSL only (builder enum is Task 4).

- [ ] **Task 3 — Builder-DSL entity key mappers.**
  Remove these 4 entries: `OdataDuty::SchemaBuilder::EntityType#int_mapper`, `#mapper`,
  `#property_ref`, `#string_mapper`. Add public-API specs under
  `spec/odata_duty/schema_builder/**` mirroring Task 1 for the builder DSL: build a schema with
  `add_entity_type` + `property_ref 'id', Integer` (unquoted `@odata.id`) and one with a String
  key (quoted), exercised via `schema.execute`; a second `property_ref` raises the same
  `RuntimeError`. Kill all survivors on the 4 subjects. `bundle exec rake` green.

- [ ] **Task 4 — Builder-DSL enum + type/container plumbing.**
  Remove these 5 entries: `OdataDuty::SchemaBuilder::EnumType#to_value`,
  `SchemaBuilder::ComplexType#property`, `SchemaBuilder::Container#initialize`,
  `SchemaBuilder::DataType#initialize`, `SchemaBuilder::DataType#scalar?`. Add public-API specs
  under `spec/odata_duty/schema_builder/**` pinning: enum `to_value` rejects a non-member with
  `OdataDuty::InvalidValue` and passes `nil` through; a bad `name:` (e.g. `add_entity_type(name:
  '9bad')`) raises `OdataDuty::InvalidNCNamesError` for both a `DataType` subtype and the
  `Container` (entity set); a duplicate property name raises
  `OdataDuty::PropertyAlreadyDefinedError`; `scalar?` is `true` for enum and `false` for
  complex/entity, observed via `$metadata`/`$oas2` placement. Kill all survivors on the 5
  subjects. `bundle exec rake` green.

- [ ] **Task 5 — Update `spec/using_mutant.md` debt count.**
  The ratchet's recorded count/rationale ("221 of 339 subjects … 3248 mutations, ~67%") is now
  stale after removing 25 entries. Update the count in `spec/using_mutant.md` to reflect the new
  ignore-list size (recompute from the final `.mutant.yml`). No other doc changes (behavior is
  unchanged); do not add a new `doc/` guide. `bundle exec rake` green.
