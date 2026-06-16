# Build plan — Flat-OR support for `$filter`

PRD: [task-tgnuvk8sffZYn9tHJs.md](./task-tgnuvk8sffZYn9tHJs.md)

Lets OData clients combine `$filter` predicates with `or` (flat single-operator OR).
Consumers opt in via a new `od_filter_or(predicates)` hook receiving `OdataDuty::FilterPredicate`
value objects. The parse + dispatch logic is **shared** by both DSLs (it lives in `filter.rb` /
`executor.rb` and dispatches on the set/resolver via `respond_to?`), so the hook works for the
class-based set and the builder resolver alike. DSL-specific work: the two spec trees, the
`supports_filter_or?` metadata predicate, and the generated AR concern.

---

## Task 1 — Core OR filtering: `FilterPredicate`, OR parsing, Executor dispatch

- [x] Done

**Task text:** Add flat single-operator OR support to `$filter`. Introduce a public read-only
value object `OdataDuty::FilterPredicate` exposing `#property_name` (Symbol), `#operation`
(Symbol, one of `:eq :ne :gt :lt :ge :le`), and `#value` (coerced to the property's type). Extend
`OdataDuty::Filter` to detect a flat ` or ` expression and reject mixing ` and ` with ` or ` in the
same expression. In `Executor#apply_filter`, when the expression is OR, build the array of
`FilterPredicate` (reusing the same property validation and `filter_convert` coercion the AND path
uses) and call the set/resolver's `od_filter_or(predicates)` **once**. The existing AND /
single-predicate path (sequential `od_filter_<prop>_<op>` / `od_filter_<op>`) is unchanged and
`od_filter_or` is not called for it. Because dispatch is on the set builder, this serves both the
class-based DSL and the builder DSL with no per-DSL code — but add specs in **both** spec trees.

**Definition of done (PRD excerpt):**
- `GET /People?$filter=status eq 'active' or status eq 'pending'` → union of both predicates.
- `GET /People?$filter=name eq 'Alice' or id gt 2` → `od_filter_or` receives
  `[FilterPredicate(name,:eq,"Alice"), FilterPredicate(id,:gt,2)]` (value coerced: `id` → Integer 2).
- AND path unchanged; `od_filter_or` not called.
- Errors: mixed AND/OR → `NotYetSupportedError` ("mixed AND/OR not supported"); parentheses →
  `NotYetSupportedError`; OR used but no `od_filter_or` → `NoImplementationError` ("OR filtering not
  supported"); unknown property → `UnknownPropertyError`; OR on a collection property →
  `InvalidQueryOptionError`; uncoercible value → existing value-coercion error (`InvalidFilterValue`).

**Likely files:** `lib/odata_duty/filter.rb`, `lib/odata_duty/executor.rb`, new
`lib/odata_duty/filter_predicate.rb` (+ require in `lib/odata_duty.rb`); specs under
`spec/odata_duty/entity_set/` (class DSL, e.g. extend/add a collection-or spec) and
`spec/odata_duty/schema_builder/entity_set/` (builder DSL).

**Depends on:** nothing.

---

## Task 2 — `$metadata` `FilterRestrictions` annotation

- [x] Done

**Task text:** Advertise OR-filter capability in `$metadata`, mirroring the `$search` precedent. Add
a `supports_filter_or?` predicate to the metadata object of **both** DSLs — class DSL
(`OdataDuty::EntitySet::Metadata` in `lib/odata_duty.rb`, `entity_set.method_defined?(:od_filter_or)`)
and builder DSL (`SchemaBuilder::EntitySet#supports_filter_or?` →
`resolver_class.method_defined?(:od_filter_or)`, surfaced through `Endpoint`). In
`lib/metadata.xml.erb`, emit a `Capabilities.FilterRestrictions` annotation for sets where
`supports_filter_or?` is true: `Filterable` Bool `true`, plus the closest standard property
signalling that grouping/parentheses are unsupported (per the PRD open question, prefer
`FilterExpressionRestrictions`). Sets without `od_filter_or` get no annotation.

**Definition of done (PRD excerpt):** `$metadata` for an OR-capable set includes
`Term="Capabilities.FilterRestrictions"` with `Property="Filterable" Bool="true"`, and signals
grouping unsupported; a set without `od_filter_or` does not include the annotation.

**Likely files:** `lib/odata_duty.rb` (Metadata), `lib/odata_duty/schema_builder/entity_set.rb`,
`lib/odata_duty/schema_builder/endpoint.rb`, `lib/metadata.xml.erb`; metadata specs in both spec
trees (alongside the existing search metadata specs).

**Depends on:** Task 1 (hook name `od_filter_or`).

---

## Task 3 — `$oas2` `$filter` description mentions OR

- [ ] Done

**Task text:** Update the `$filter` OAS2 parameter description to mention OR support. No schema
change — `$filter` stays a freeform query string. Update the existing `$filter` parameter
assertions in both spec trees' OAS2 tests.

**Definition of done (PRD excerpt):** "`$oas2` — no schema change; `$filter` remains a freeform
string parameter (its description is updated to mention OR)."

**Likely files:** `lib/odata_duty/oas2/collection_get_path.rb`; OAS2 specs in both spec trees
(`spec/odata_duty/entity_set/select_spec.rb` / `schema_builder` collection/search specs that assert
the `$filter` parameter description).

**Depends on:** Task 1.

---

## Task 4 — Generator default `od_filter_or` in the AR concern

- [ ] Done

**Task text:** Ship a default `od_filter_or` in the generated ActiveRecord concern so freshly
generated sets serve OR queries with no extra code. It builds a union across the operations the
concern already supports (`eq, ne, gt, lt, ge, le`) and assigns the union back to `@records`. Keep
within RuboCop metrics. Update/extend the generator spec to assert the concern includes
`od_filter_or` and that the template is valid Ruby.

**Definition of done (PRD excerpt):** "the `odata_duty:entity_set` generator's concern ships a
default `od_filter_or` that builds a union across the operations it already supports (`eq, ne, gt,
lt, ge, le`), so freshly generated sets serve OR queries with no extra code."

**Likely files:**
`lib/generators/odata_duty/entity_set/templates/odata_active_record_concern.rb.erb`;
`spec/generators/entity_set_generator_spec.rb`.

**Depends on:** Task 1 (FilterPredicate contract: `p.property_name`, `p.operation`, `p.value`).

---

## Task 5 — README mention of OR `$filter`

- [ ] Done

**Task text:** Mention flat OR `$filter` support and the `od_filter_or` hook in `README.md` near the
existing `od_filter_*` example. Do **not** add `doc/using_filter.md` — the PRD gates the full guide
on explicit request, which was not given.

**Definition of done (PRD excerpt):** "mention OR support in `README.md` ... Guide to be written
only on request."

**Likely files:** `README.md`.

**Depends on:** Tasks 1–4.
