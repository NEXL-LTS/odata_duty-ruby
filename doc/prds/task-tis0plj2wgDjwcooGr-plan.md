# Build plan — Kill mutant survivors for the 29 non-MCP ignored subjects

PRD: [task-tis0plj2wgDjwcooGr.md](./task-tis0plj2wgDjwcooGr.md)

Test-quality debt cleanup. For each task: **remove** the listed subjects from
`.mutant.yml`'s `matcher: ignore:`, run `bundle exec mutant run '<subject>'`, and drive it to
**zero surviving mutations** — killing each survivor with a public-API spec (both spec trees where
the subject spans both DSLs) or accepting a mutation that proves internal code redundant (observable
output must stay identical). Finish every task on a green `bundle exec rake` (RSpec + RuboCop + 100%
coverage). No consumer-facing behavior change.

Rules baked into every task: public-API-only specs (`AGENTS.md`), TDD, 99-char lines, RuboCop
metrics (MethodLength 13, AbcSize 30, CyclomaticComplexity 7), keep both DSLs in sync.

## Tasks

- [x] **Task 1 — `$filter` subjects.**
  Remove and kill survivors for `OdataDuty::Filter#initialize`, `OdataDuty::Filter#operation`,
  `OdataDuty::Filter.split_outside_quotes`, `OdataDuty::Filter.validate`.
  Files: `lib/odata_duty/filter.rb`; specs under `spec/odata_duty/entity_set/filter_*` and
  `spec/odata_duty/schema_builder/entity_set/filter_*` (both DSLs — `$filter` surfaces in both).
  PRD excerpt: "`?$filter=name eq 'Smith, John'` reaches `od_filter_eq('name', 'Smith, John')` as
  one value"; quoted values, multi-clause AND/OR filters, invalid filters raising
  `InvalidQueryOptionError`/`NotYetSupportedError`. Deps: none.

- [x] **Task 2 — `$metadata` EDMX XML.**
  Remove and kill survivors for `OdataDuty::EdmxSchema.metadata_xml`.
  Files: `lib/odata_duty/edmx_schema.rb`, `lib/metadata.xml.erb`; specs asserting `Schema.metadata_xml`
  / `SchemaBuilder` metadata XML output (both DSLs). Deps: none.

- [x] **Task 3 — `RequestError#initialize` / error responses.**
  Remove and kill survivors for `OdataDuty::RequestError#initialize`.
  Files: `lib/odata_duty/errors.rb`; specs asserting error class/message/code/target/status through
  the public API (bad requests). Deps: none.

- [x] **Task 4 — `SetResolver` lifecycle (builder DSL).**
  Remove and kill survivors for `OdataDuty::SetResolver#entity_set`,
  `OdataDuty::SetResolver#handle_init_args_error`, `OdataDuty::SetResolver#initialize`,
  `OdataDuty::SetResolver#od_next_link_skiptoken`.
  Files: `lib/odata_duty/set_resolver.rb`; specs under `spec/odata_duty/schema_builder/**`
  (builder-DSL-specific — `resolver:` via `SchemaBuilder`). PRD excerpt: `od_after_init` init-args
  error path; `@odata.nextLink` with expected `$skiptoken` on a paged collection, omitted on the
  final page. Deps: none.

- [x] **Task 5 — Property declaration & mutability.**
  Remove and kill survivors for `OdataDuty::Property.new`, `OdataDuty::Property.resolve_mutability`,
  `OdataDuty::Property.valid_name?`.
  Files: `lib/odata_duty/property.rb`; specs asserting `property` declarations, `computed`/`immutable`/
  `non_insertable` reflected in `$metadata`/`$oas2`, invalid property names raising
  `InvalidNCNamesError`, and the `mutability:`/`computed:` conflict + invalid-mutability
  `ArgumentError`s. Both DSLs. Deps: none.

- [x] **Task 6 — Property value & type conversion.**
  Remove and kill survivors for `OdataDuty::Property::CollectionProp#convert`,
  `OdataDuty::Property::SingleProp#calling_method?`, `#collection?`, `#convert`, `#filter_convert`,
  `#initialize`, `#load_type_instance_vars`, `#to_oas2_type`, `#to_value`.
  Files: `lib/odata_duty/property/single_prop.rb`, `lib/odata_duty/property/collection_prop.rb`;
  specs asserting typed values in JSON output, `$filter` value coercion (`InvalidFilterValue`),
  `$oas2` type/format per property type (e.g. `DateTimeOffset` → `string`/`date-time`),
  collection-valued properties, `method:` proc vs symbol. Both DSLs. Deps: none.

- [x] **Task 7 — `MapperBuilder` object→JSON serialization.**
  Remove and kill survivors for `OdataDuty::MapperBuilder#confirm_boolean`, `#confirm_one_of`,
  `#obj_to_base_hash`, `#obj_to_hash`, `.build_class`, `.eval_erb_class`.
  Files: `lib/odata_duty/mapper_builder.rb`, `lib/odata_duty/dynamic_object_wrapper.rb.erb`;
  specs asserting collection/individual JSON bodies, `Boolean` coercion (both branches),
  `Enum` one-of validation (member vs non-member raising `InvalidValue`), nil handling. Both DSLs.
  Deps: none.

- [x] **Task 8 — Update the ratchet count in `spec/using_mutant.md`.**
  Change the documented shrink count ("47 entries") to the post-cleanup number (18). Note only.
  Deps: Tasks 1–7 (all 29 entries removed).
