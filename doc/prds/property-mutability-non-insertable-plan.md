# Build plan: Non-insertable (update-only) properties

PRD: [`property-mutability-non-insertable.md`](property-mutability-non-insertable.md)

Adds a fourth `mutability:` value, `:non_insertable` — settable on update, dropped on create,
advertised as insert-restricted in `$metadata` and excluded from the MCP create tool. Builds on
Part A (`:immutable`/`:computed`). `$oas2` is explicitly **out of scope** (Part C).

Core mutability code (`lib/odata_duty/property.rb`, `property/single_prop.rb`) and the typed-input
wrapper / MCP schema builders are **shared** by both DSLs, so a single change there serves both;
only the entity-set metadata accessor and specs are duplicated per DSL. Every task names both
spec trees.

---

## Task 1 — Accept `:non_insertable`; settability drives typed input + MCP tools

- [x] **Status** — done

**Task text:** Add `:non_insertable` as a fourth accepted `mutability:` value. Update declaration-time
validation so it is accepted and the rejected-symbol error message lists all four valid values
(`:read_write`, `:immutable`, `:non_insertable`, `:computed`). Implement the settability semantics:
`:non_insertable` is **not** settable on create (silently dropped, no `InvalidType` even for a
wrong-typed value, reads back as `nil` inside `create`) and **is** settable on update (coerced and
present inside `update`). Because the MCP `create_<Set>` / `update_<Set>` input schemas are built from
the same `settable_on_create?` / `settable_on_update?` predicates, the create tool must exclude and the
update tool must include `:non_insertable` properties once the predicates are correct. Cover both DSLs
and both spec trees.

**Likely files:**
- `lib/odata_duty/property.rb` — add `:non_insertable` to `MUTABILITIES`; error message lists four values.
- `lib/odata_duty/property/single_prop.rb` — add `non_insertable?`; fix `settable_on_create?` (false for
  `:computed` **and** `:non_insertable`) and `settable_on_update?` (true for `:read_write` **and**
  `:non_insertable`).
- (Shared) `lib/odata_duty/create_complex_type_hash_wrapper.rb` and `lib/odata_duty/mcp_input_schemas.rb`
  should need **no** change — they already dispatch on the predicates. Confirm.
- Specs (class DSL): `spec/odata_duty/entity_set/mutability_spec.rb` (extend), new
  `spec/odata_duty/entity_set/update/non_insertable_spec.rb`,
  `spec/odata_duty/entity_set/create/mcp_non_insertable_spec.rb`,
  `spec/odata_duty/entity_set/update/mcp_non_insertable_spec.rb`.
- Specs (builder DSL): `spec/odata_duty/schema_builder/entity_set/mutability_spec.rb` (extend), and the
  sibling `update/non_insertable_spec.rb`, `create/mcp_non_insertable_spec.rb`,
  `update/mcp_non_insertable_spec.rb` under `spec/odata_duty/schema_builder/entity_set/`.

**Defining PRD excerpt:**
- `input.status # => nil` on create (`:non_insertable` ignored), `input.note # => "x"`.
- `input.status # => "closed"` on update (settable). No error / no `InvalidType` for a value sent on
  create — silently dropped.
- create tool: `:non_insertable` absent from `inputSchema.properties`. update tool: present.
- `mutability: :non_insertable` accepted; rejected-symbol error lists all four valid values.

**Dependencies:** none.

---

## Task 2 — `$metadata`: `InsertRestrictions/NonInsertableProperties`

- [ ] **Status**

**Task text:** Emit each `:non_insertable` property as a `NonInsertableProperties` collection entry in the
entity set's `Capabilities.InsertRestrictions` annotation. It must compose with the existing set-level
`Insertable: false` annotation (emitted when there is no `create`) — both appear in the same
`<Record>` when both apply. Read responses and property-level Core annotations are unchanged
(`:non_insertable` has no Core term). Cover both DSLs and both spec trees.

**Likely files:**
- `lib/metadata.xml.erb` — extend the `InsertRestrictions` block to render when there is no create **or**
  any non-insertable property; add the `NonInsertableProperties`/`Collection`/`PropertyPath` markup.
- `lib/odata_duty.rb` (`Metadata` class) and `lib/odata_duty/schema_builder/entity_set.rb` — add a
  symmetric `non_insertable_property_names` helper so the erb stays DSL-agnostic.
- Specs: `spec/odata_duty/entity_set/non_insertable_metadata_spec.rb` and
  `spec/odata_duty/schema_builder/entity_set/non_insertable_metadata_spec.rb`.

**Defining PRD excerpt:**
```xml
<Annotation Term="Capabilities.InsertRestrictions">
    <Record>
        <PropertyValue Property="NonInsertableProperties">
            <Collection>
                <PropertyPath>status</PropertyPath>
            </Collection>
        </PropertyValue>
    </Record>
</Annotation>
```
Composes with the set-level `Insertable: false`. Metadata XML stays well-formed.

**Dependencies:** Task 1 (the `non_insertable?` predicate).

---

## Task 3 — Documentation + Features index

- [ ] **Status**

**Task text:** Extend `doc/using_mutability.md` with the `:non_insertable` row in the overview table and
its create/update/`$metadata`/MCP behavior, including the note that `$oas2` is unchanged here (Part C).
Update the `## Features` line for property mutability in `CLAUDE.md` to mention `:non_insertable` and the
`Capabilities.InsertRestrictions` reflection, still pointing at `doc/using_mutability.md`.

**Likely files:** `doc/using_mutability.md`, `CLAUDE.md`.

**Defining PRD excerpt:** "Extend **`doc/using_mutability.md`** (created in Part A) with the
`:non_insertable` row and its create/update/`$metadata`/MCP behavior. No new guide."

**Dependencies:** Tasks 1–2 (documents their behavior).
