# Build plan — Retire the `EntitySet::Metadata` mutation-testing debt

PRD: [task-thtnu86mu7tkh6jTr6.md](./task-thtnu86mu7tkh6jTr6.md)

Goal: remove the twenty `EntitySet::Metadata` (class DSL) and `SchemaBuilder::Endpoint` /
`SchemaBuilder::EntitySet` (builder DSL) entries from `.mutant.yml`'s `ignore:` list by
pinning the consumer-observable contracts through public-API specs (and a few accept-mutation
lib simplifications + one builder message fix). Every removed subject must finish
survivor-free under `bundle exec mutant run '<subject>'`, and `bundle exec rake` stays green.

Subjects split so each task owns a disjoint set of subjects and removes exactly its own
`.mutant.yml` entries, verifying those subjects survivor-free with mutant.

Class DSL (11): `#collection #converted_id #create #delete #individual #kind #metadata_types
#name #new_entity_set #non_insertable_property_names #update`
Builder DSL (9): `Endpoint#{collection,converted_id,create,delete,extend_error,individual,update}`,
`EntitySet#{initialize,non_insertable_property_names}`

---

## Task 1 — Class DSL read paths: `#collection`, `#individual`, `#converted_id`

- [x] Done

**Subjects / entries to remove:** `OdataDuty::EntitySet::Metadata#collection`,
`#individual`, `#converted_id`.

**Task text:** Pin, through the class-DSL public API (`Schema.execute`), the read-path
contracts so mutant finds no survivors on `#collection`, `#individual`, `#converted_id`.
Add/extend specs under `spec/odata_duty/entity_set/**` that assert:
- the exact `NoImplementationError` messages `collection not implemented for <Set>` and
  `individual not implemented for <Set>` (`<Set>` = the `EntitySet` subclass name);
- `ResourceNotFoundError` message `No such entity <id>` on `Set(id)` for a missing entity;
- `InvalidPropertyReferenceValue` message `Invalid individual id : <reason>` when the id
  fails key coercion;
- a property method that reads `od_context` observably (e.g. embeds `od_context.od_full_url`)
  so the collection and individual read paths both thread the request context into
  `obj_to_hash` (kills the `obj_to_hash(result, nil)` context-arg mutant).
Accept the "likely equivalent" mutants noted in the PRD (`converted_id(id, nil)`,
`convert(id, nil)`, `"#{e.message}"` vs `"#{e}"`) only if mutant confirms them unkillable
through the public API. Then delete the three entries from `.mutant.yml` and run
`bundle exec mutant run 'OdataDuty::EntitySet::Metadata#collection' \
'OdataDuty::EntitySet::Metadata#individual' 'OdataDuty::EntitySet::Metadata#converted_id'`
to confirm 0 alive. Finish on green `bundle exec rake`.

**Likely files:** `spec/odata_duty/entity_set/{collection_spec,individual_spec,context_spec}.rb`,
`.mutant.yml`. (lib may need no change if all survivors are killed by specs.)

**PRD excerpt (definition of done):** Pinned error messages table (rows: collection/individual
not implemented, `No such entity <id>`, `Invalid individual id : <reason>`); Resolution guide
groups "Error-message mutants" and "`obj_to_hash(result, nil)`"; External API §2 request context
in property methods.

**Depends on:** none.

---

## Task 2 — Class DSL write paths: `#create`, `#update`, `#delete`, `#new_entity_set`

- [x] Done

**Subjects / entries to remove:** `OdataDuty::EntitySet::Metadata#create`, `#update`,
`#delete`, `#new_entity_set`.

**Task text:** Pin the class-DSL write-path contracts through the public API
(`Schema.create` / `.update` / `.delete`). Add/extend specs under
`spec/odata_duty/entity_set/{create,update,delete}/**` that assert:
- `ResourceNotFoundError` message `No such entity <id>` for update/delete of a missing entity;
- a property method reading `od_context` observably on the create and update response payloads
  (kills the `obj_to_hash(result, nil)` context-arg mutant on `#create`/`#update`);
- the `create`/`update`/`delete` hook can read the live `context` reader and the resulting
  record reflects it (kills `entity_set.new(context: nil)` write-hook context mutant).
Apply the accept-mutation simplification on `#delete`: drop the trailing `result` (return value
is never observed; the REST response is the `@odata.context`-only acknowledgement either way) —
verify `bundle exec rake` green after. `#new_entity_set` has zero survivors; just delete its
entry. Delete the four entries from `.mutant.yml` and run
`bundle exec mutant run 'OdataDuty::EntitySet::Metadata#create' '...#update' '...#delete' \
'...#new_entity_set'` to confirm 0 alive. Finish on green `bundle exec rake`.

**Likely files:** `lib/odata_duty.rb` (`#delete`), `spec/odata_duty/entity_set/create/**`,
`.../update/**`, `.../delete/**`, `.../context_spec.rb`, `.mutant.yml`.

**PRD excerpt:** Pinned error messages table; Resolution guide "Write-hook context",
"`obj_to_hash(result, nil)`", and accept "`#delete`: drop the trailing `result`"; External API §3
resolver context in write hooks; note `#new_entity_set` has no survivors.

**Depends on:** Task 1 (context-reading property-method test helper pattern).

---

## Task 3 — Class DSL metadata/naming: `#kind`, `#metadata_types`, `#name`, `#non_insertable_property_names`

- [x] Done

**Subjects / entries to remove:** `OdataDuty::EntitySet::Metadata#kind`, `#metadata_types`,
`#name`, `#non_insertable_property_names`.

**Task text:** Pin the class-DSL metadata contracts through the public API (`Schema.index_hash`
/ `.metadata_xml`). Add/extend specs under `spec/odata_duty/entity_set/**` that assert:
- `"kind": "EntitySet"` appears in the index (service) document for an entity set entry;
- the default name derivation: a class named `<X>EntitySet` and one named `<X>Set` both expose
  entity set `<X>` in the index document **and** `$metadata` (kills the two `\z`-anchored suffix
  strips);
- `Capabilities.InsertRestrictions/NonInsertableProperties` renders each
  `mutability: :non_insertable` property as an exact `<PropertyPath>` in `$metadata`.
Apply the accept-mutation simplifications: `#name` `gsub`→`sub` on both `\z`-anchored suffixes
(matching `ComplexType::Metadata#name`); `#metadata_types` drop `.uniq` (schema-level
`metadata_types` already uniqs) and use the `entity_type` reader instead of
`entity_set.entity_type`; `#non_insertable_property_names` use `entity_type.properties`
(same collection as `entity_type.__metadata.properties`). Delete the four entries from
`.mutant.yml`; run `bundle exec mutant run 'OdataDuty::EntitySet::Metadata#kind' '...#metadata_types'
'...#name' '...#non_insertable_property_names'` → 0 alive. Green `bundle exec rake`.

**Likely files:** `lib/odata_duty.rb`,
`spec/odata_duty/entity_set/{set_name_and_url_spec,non_insertable_metadata_spec,metadata_coverage_spec}.rb`,
`.mutant.yml`.

**PRD excerpt:** External API §1 default naming (class DSL); Behavior "Service (index) document"
`kind` and "`$metadata` NonInsertableProperties" `<PropertyPath>`; Resolution guide "Name
derivation" (class DSL), "`#kind`", "`non_insertable_property_names`", and the four accepts
under "Accept — dead/redundant code".

**Depends on:** Task 1.

---

## Task 4 — Builder DSL read + write paths + message fix

- [x] Done

**Subjects / entries to remove:** `OdataDuty::SchemaBuilder::Endpoint#collection`,
`#individual`, `#converted_id`, `#create`, `#update`, `#delete`.

**Task text:** Mirror the class-DSL read/write pins for the builder DSL, and apply the PRD's
one message change. Add/extend specs under `spec/odata_duty/schema_builder/entity_set/**`
(with `SetResolver` subclasses referenced by string name) that assert:
- `NoImplementationError` messages `collection not implemented for <Resolver>` and
  `individual not implemented for <Resolver>` — where `<Resolver>` is the **resolver class
  name** (matching the existing `$top not implemented for <Resolver>` convention), NOT the
  `#<OdataDuty::SchemaBuilder::EntitySet:0x...>` object. This requires fixing
  `lib/odata_duty/schema_builder/endpoint.rb` to interpolate the resolver class instead of the
  `entity_set` object — write the failing spec first.
- `ResourceNotFoundError` `No such entity <id>` and `InvalidPropertyReferenceValue`
  `Invalid individual id : <reason>`;
- a property method / mapping that reads `od_context` observably on collection, individual,
  create, and update response paths (kills `obj_to_hash(result, nil)` context mutants);
- the `create`/`update`/`delete` resolver hook reads the live `context` and the record reflects
  it (kills the `new_entity_set(context: nil)` mutant).
Apply the `#delete` accept (drop trailing `result`) in `endpoint.rb` too if mutant flags it.
Accept the same "likely equivalent" mutants as Task 1 where unkillable. Delete the six entries;
run `bundle exec mutant run 'OdataDuty::SchemaBuilder::Endpoint#collection' '...#individual'
'...#converted_id' '...#create' '...#update' '...#delete'` → 0 alive. Green `bundle exec rake`.

**Likely files:** `lib/odata_duty/schema_builder/endpoint.rb`,
`spec/odata_duty/schema_builder/entity_set/{collection_spec,individual_spec,context_spec,create/**,update/**,delete/**}`,
`.mutant.yml`.

**PRD excerpt:** Pinned error messages table + the `<Implementer>` paragraph (builder-DSL
message change to name the resolver class); Resolution guide "Error-message mutants",
"`obj_to_hash(result, nil)`", "Write-hook context"; External API §2/§3.

**Depends on:** Tasks 1–3 (patterns), independent lib file (`endpoint.rb`).

---

## Task 5 — Builder DSL `Endpoint#extend_error` + `EntitySet#initialize` + `EntitySet#non_insertable_property_names`

- [x] Done

**Subjects / entries to remove:** `OdataDuty::SchemaBuilder::Endpoint#extend_error`,
`OdataDuty::SchemaBuilder::EntitySet#initialize`,
`OdataDuty::SchemaBuilder::EntitySet#non_insertable_property_names`.

**Task text:** Pin the remaining builder-DSL subjects through the public API. Add/extend specs
under `spec/odata_duty/schema_builder/entity_set/**` that assert:
- **Backtrace decoration** (External API §1b): when a builder resolver's `collection` /
  `individual` raises a `StandardError`, the propagated error's backtrace is prefixed — in
  order — by the resolver's own method `path:line`, then its `od_after_init` `path:line` (only
  when the resolver defines `od_after_init`), then the `add_entity_set` call-site `path:line`.
  Cover both the with-`od_after_init` and without-`od_after_init` guard cases, and the ordering.
  Accept the `raise(err)` → `raise` equivalent mutant.
- **Default name derivation (builder DSL):** a namespaced resolver string
  `'Admin::PeopleResolver'` with no `name:` derives entity set name `People` (kills
  `split('::')` and `sub(/Resolver$/,'')`); accept `/Resolver$/` vs `/Resolver\z/`.
- **`initialize` defensive copying:** `name`/`url`/`resolver` are returned frozen, and mutating
  the caller's original `resolver`/`name`/`url` strings after `add_entity_set` does not change
  the schema's derived names/URLs; accept any copy that is genuinely unobservable.
- **`init_args: :_od_none_` sentinel:** a resolver whose `od_after_init` takes no arguments
  works when `add_entity_set` is called without `init_args:` (per `doc/using_init_args.md`).
- **`non_insertable_property_names`:** `$metadata` renders exact `<PropertyPath>` entries for a
  builder-DSL non-insertable property.
Delete the three entries; run `bundle exec mutant run 'OdataDuty::SchemaBuilder::Endpoint#extend_error'
'OdataDuty::SchemaBuilder::EntitySet#initialize' '...EntitySet#non_insertable_property_names'`
→ 0 alive. Green `bundle exec rake`.

**Likely files:**
`spec/odata_duty/schema_builder/entity_set/{entity_set_name_spec,od_after_init_spec,non_insertable_metadata_spec}.rb`,
new backtrace spec, `.mutant.yml`.

**PRD excerpt:** External API §1 (builder naming) + §1b (backtrace decoration); Resolution guide
"Name derivation" (builder), "`Endpoint#extend_error`", "`SchemaBuilder::EntitySet#initialize`
clone/freeze", "`init_args: :_od_none_` sentinel", "`non_insertable_property_names`".

**Depends on:** Task 4 (builder resolver test patterns).

---

## Task 6 — Documentation + gemspec bump

- [ ] Not started

**Task text:** Update docs and version per the PRD's Documentation impact:
- Extend `doc/using_context.md` with a section on reading the request context inside entity-type
  property methods (`od_context`, `object`), mirroring External API §2's snippet.
- Update `README.md` to note both default naming conventions where each DSL is introduced:
  `<X>EntitySet` / `<X>Set` → `<X>` (class DSL) and `<Namespace>::<X>Resolver` → `<X>`
  (builder DSL); optionally a short mention of the builder-DSL backtrace decoration.
- Bump `spec.version` patch in `odata_duty.gemspec` (0.21.5 → 0.21.6).
- Update the `## Features` index in `CLAUDE.md` only if a note-worthy externally visible
  capability was added — here the changes are documentation of existing behavior, so update the
  relevant existing entries' guides rather than adding new lines (judgment call: the
  `od_context`/`object` readers becoming documented contract belongs under
  `doc/using_context.md`, already linked).
Green `bundle exec rake` (RuboCop lints markdown? no — just ensure suite passes).

**Likely files:** `doc/using_context.md`, `README.md`, `odata_duty.gemspec`, possibly `CLAUDE.md`.

**PRD excerpt:** Documentation impact section; Scope "Document `od_context`/`object`, both naming
conventions, and the backtrace decoration"; "Gemspec patch version bump in the same change as
the `lib/` edits."

**Depends on:** Tasks 1–5.
