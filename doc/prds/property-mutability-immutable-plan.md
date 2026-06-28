# Build plan: Immutable (create-only) properties + the `mutability:` foundation

> PRD: [`property-mutability-immutable.md`](property-mutability-immutable.md)

Decomposition of the PRD into ordered, testable tasks. Both DSLs share
`OdataDuty::Property` (the builder DSL's `SchemaBuilder::ComplexType#property` calls
`OdataDuty::Property.new`), so the keyword/validation lands once in `lib/odata_duty/property.rb`
+ `property/single_prop.rb`; the `property_ref` defaults differ per DSL
(`lib/odata_duty/entity_type.rb` vs `lib/odata_duty/schema_builder/entity_type.rb`). The
create/update typed-input wrapper (`create_complex_type_hash_wrapper.rb`) is shared by both
`create` and `update` (see `lib/odata_duty.rb` `Metadata#create`/`#update`), so immutable
enforcement needs an operation flag threaded through.

Predicate model on a property:
- `mutability` ∈ `{:read_write, :immutable, :computed}` (default `:read_write`).
- `computed?` ⇔ `mutability == :computed` (kept as-is — backward compatible).
- `immutable?` ⇔ `mutability == :immutable`.
- `settable_on_create?` ⇔ `mutability != :computed` (read_write + immutable).
- `settable_on_update?` ⇔ `mutability == :read_write`.

---

## Task 1 — `mutability:` keyword foundation: resolution, validation, predicates, key defaults

**Task text:** Add a `mutability:` keyword to `property` and `property_ref` accepting
`:read_write` (default), `:immutable`, `:computed`. Resolve it in `OdataDuty::Property.new`:
`computed: true` aliases `:computed`, `computed: false` aliases `:read_write`; passing both
`mutability:` and `computed:` raises `ArgumentError` (same axis); an unknown `mutability:`
value (e.g. `:frozen`) raises `ArgumentError` naming the property and the bad value. Store
`mutability` on `SingleProp` and expose `computed?` (unchanged meaning), `immutable?`,
`settable_on_create?`, `settable_on_update?`. `property_ref` in **both** DSLs defaults to
`mutability: :computed` (today's "keys are computed by default"), still overridable with
`computed: false` or `mutability: :read_write`. No behavior change to existing `computed:`
schemas.

**Likely files:** `lib/odata_duty/property.rb`, `lib/odata_duty/property/single_prop.rb`,
`lib/odata_duty/entity_type.rb`, `lib/odata_duty/schema_builder/entity_type.rb`. Specs:
`spec/odata_duty/entity_set/mutability_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/mutability_spec.rb`.

**PRD excerpt (done):** "A symbol outside `{:read_write, :immutable, :computed}` (e.g.
`mutability: :frozen`) raises an `ArgumentError` when the schema is defined, naming the
property and the bad value." / "Both `mutability:` and `computed:` on one property → raises
`ArgumentError`." / "`computed: true` is retained as a backwards-compatible alias for
`mutability: :computed`; `computed: false` aliases `:read_write`." / "`property_ref` (keys)
default to `mutability: :computed` … Opt back in with `mutability: :read_write` (equivalently
`computed: false`)."

**Depends on:** nothing.

- [ ] Done

## Task 2 — `:immutable` enforcement: silent drop on update in the typed input

**Task text:** Thread the operation (`:create` / `:update`) into the shared typed-input wrapper
so that, inside `update(id, input)`, an `:immutable` property reads back as `nil` regardless of
the request body (silently — no error, no `InvalidType` even for a wrong-typed value), while
inside `create(input)` an `:immutable` property is coerced and present as normal. `:computed`
stays dropped on both; `:read_write` flows through on both. Implement in **both** DSLs (the
wrapper and `lib/odata_duty.rb` are shared; verify the builder path).

**Likely files:** `lib/odata_duty/create_complex_type_hash_wrapper.rb`, `lib/odata_duty.rb`.
Specs: `spec/odata_duty/entity_set/update/immutable_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/update/immutable_spec.rb` (and create-side coverage
that immutable is present on create).

**PRD excerpt (done):** PATCH inside `update`: `input.account_number # => nil` (immutable,
frozen on update, ignored), `input.note # => "done"`. POST inside `create`:
`input.account_number # => "A-100"` (settable on create), `input.created_at # => nil`
(computed). "Immutable value supplied on update → silently ignored. No error, and no
`OdataDuty::InvalidType` even for a wrong-typed value; reads back as `nil`."

**Depends on:** Task 1.

- [ ] Done

## Task 3 — `$metadata` (EDMX) `Core.Immutable` annotation

**Task text:** Render `<Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />` on the
`<Property>` for an `:immutable` property; `:computed` keeps `Core.Computed`; `:read_write`
gets no annotation. Applies to both `ComplexType` and `EntityType` property blocks in the
shared `lib/metadata.xml.erb`. The `Core` vocabulary reference already exists — no new
reference. Both DSLs render from the same template.

**Likely files:** `lib/metadata.xml.erb` (optionally a small annotation-term helper on the
property/metadata to keep the ERB clean). Specs:
`spec/odata_duty/entity_set/immutable_metadata_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/immutable_metadata_spec.rb`.

**PRD excerpt (done):**
```xml
<Property Name="account_number" Nullable="false" Type="Edm.String">
    <Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />
</Property>
```
`:computed` → `Core.Computed` (unchanged). `:read_write` → no annotation.

**Depends on:** Task 1.

- [ ] Done

## Task 4 — MCP: `create_<Set>` includes immutable, `update_<Set>` excludes it

**Task text:** The `create_<Set>` tool's `inputSchema` **includes** `:immutable` properties
(settable on create) and still excludes `:computed`. The `update_<Set>` tool's `inputSchema`
**excludes** `:immutable` properties in addition to `:computed` (an immutable field cannot be
sent on update). Drive both from the new predicates (`settable_on_create?` /
`settable_on_update?`). Both DSLs use the shared `mcp_input_schemas.rb`.

**Likely files:** `lib/odata_duty/mcp_input_schemas.rb`. Specs:
`spec/odata_duty/entity_set/update/mcp_immutable_spec.rb` (or extend create/update mcp specs)
and the sibling under `spec/odata_duty/schema_builder/entity_set/update/`.

**PRD excerpt (done):** update tool — `account_number` (immutable) and `created_at` (computed)
absent, only `id`/`note`. create tool — `account_number` (immutable) present, `id`/`created_at`
(computed) absent, `required: ["account_number"]`.

**Depends on:** Task 1.

- [ ] Done

## Task 5 — Documentation + `## Features` index

**Task text:** Add **`doc/using_mutability.md`** covering the `mutability:` axis and `:immutable`
(create/update/read matrix, `$metadata` + MCP reflection, note `$oas2` is addressed in a
follow-up). Update **`doc/using_computed.md`** to state `computed:` is now the `:computed` alias
of `mutability:` and link to the new guide. Add a one-line entry to the `## Features` index in
`CLAUDE.md` pointing at `doc/using_mutability.md`.

**Likely files:** `doc/using_mutability.md` (new), `doc/using_computed.md`, `CLAUDE.md`.

**PRD excerpt (done):** "Documentation impact" section of the PRD.

**Depends on:** Tasks 1–4.

- [ ] Done
