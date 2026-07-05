# Build plan — Request context & typed-input contracts (mutation-ratchet burn-down)

PRD: [task-thoz7al5u693wvfbFi.md](./task-thoz7al5u693wvfbFi.md)

Burns down 7 `.mutant.yml` ratchet entries (42 alive mutations) by pinning two consumer-facing
surfaces with documentation-style specs in both DSL trees, simplifying behaviorally-equivalent
mutants, adding/extending docs, and deleting the ratchet entries.

Target subjects: `OdataDuty::ContextWrapper#initialize`, `#od_full_url`;
`OdataDuty::CreateComplexTypeHashWrapper#initialize`, `#__load`, `#__wrap`, `#method_missing`,
`#respond_to_missing?`.

Definition of done for the whole PRD: `bundle exec mutant run 'OdataDuty::ContextWrapper*'
'OdataDuty::CreateComplexTypeHashWrapper*'` reports 100% with all 7 entries deleted; `bundle exec
rake` green.

Rules honored by every task: TDD (failing spec first, public API only), both DSLs + both spec
trees where applicable, 99-char lines, RuboCop metrics, `bundle exec rake` green, no new API
surface, no `$metadata`/`$oas2`/MCP output change.

---

## Task 1 — ContextWrapper consumer contracts + equivalent-mutant simplification

**Text:** Add documentation-style specs (both `spec/odata_duty/entity_set/**` and
`spec/odata_duty/schema_builder/**`) pinning the request-context object handed to resolver hooks:
(a) *delegation* — any method call on `context` delegates to the caller-supplied `context:` object
passed to `schema.execute`/`.create`/`.update`/`.delete`; (b) `od_full_url(path, anchor:,
**query_params)` returns a `String` = base URL + `/` + path, `?`-www-form-encoded query params,
`#anchor` fragment; (c) `query_options` reads back as a plain `Hash` even when a `#to_h`-able
hash-like object (e.g. Rails params) was passed as `query_options:`; (d) `base_url` has no trailing
`/`; (e) `current` is a per-request memo `Hash`, initially empty. Then simplify the behaviorally-
equivalent mutants in `ContextWrapper#initialize` (dead keyword default / redundant `.to_h`) and
`#od_full_url` (identity `path.split('/')…join('/')`, no-op `.compact` guard) — only where there is
no observable behavior change; if a simplification *would* change behavior, stop and surface it.
Delete the two `.mutant.yml` entries (`ContextWrapper#initialize`, `#od_full_url`) and confirm
`bundle exec mutant run 'OdataDuty::ContextWrapper*'` is 100%. Bump `spec.version` 0.21.3 → 0.21.4.

**Likely files:** `lib/odata_duty/context_wrapper.rb`, `.mutant.yml`, `odata_duty.gemspec`,
new specs under both spec trees.

**PRD excerpt (done):** External-API table (delegation, `od_full_url`, `query_options`, `base_url`,
`current`); `od_full_url` examples → `"https://example.org/odata/People"`,
`?top=5`, `$metadata#People`; `query_options` normalization → `{ '$top' => '1' }` plain Hash.

**Depends on:** none.

- [x] Done

## Task 2 — CreateComplexTypeHashWrapper error contracts + method_missing simplification

**Text:** Add documentation-style specs (both trees) for the typed-input object handed to
`create`/`update`: (a) reading an undefined property raises `OdataDuty::NoSuchPropertyError` with
message exactly `No such property 'nickname'`; (b) calling a property accessor with arguments
(`input.first_name('x')`) also raises `OdataDuty::NoSuchPropertyError` (accessors take no args).
Then simplify the behaviorally-equivalent mutants in `#method_missing`, `#respond_to_missing?`
(redundant `.to_sym` on an already-symbol `method_name`; unobservable `rescue NoMethodError` path)
and `#initialize` (dead keyword default) — equivalence only; surface if behavior would change.
Delete the `.mutant.yml` entries for `#initialize`, `#method_missing`, `#respond_to_missing?` and
confirm those subjects are 100% under mutant.

**Likely files:** `lib/odata_duty/create_complex_type_hash_wrapper.rb`, `.mutant.yml`, new specs
under both spec trees.

**PRD excerpt (done):** "Undefined property read → `OdataDuty::NoSuchPropertyError` with message
`No such property 'nickname'`"; "Property accessor called with arguments (`input.first_name('x')`)
→ also `OdataDuty::NoSuchPropertyError`; accessors take no arguments."

**Depends on:** none (independent subjects from Task 1).

- [ ] Done

## Task 3 — Nested-input mutability contracts + __load/__wrap simplification

**Text:** Add documentation-style specs (both trees) proving property `mutability:` applies to
*nested* complex-type values exactly as at top level: on POST, a nested `:non_insertable` value is
silently dropped (reads back `nil`); on PATCH, a nested `:immutable` value is silently dropped
(reads back `nil`) while a writable nested value passes through; the same holds one level deeper
(complex-within-complex) and for collections of complex values; a nested wrong-typed value on a
writable property still raises `OdataDuty::InvalidType`. Then simplify the behaviorally-equivalent
mutants in `#__load` (unused coercion argument) and `#__wrap` (dead keyword default) — equivalence
only; surface if behavior would change. Delete the `.mutant.yml` entries for `#__load`, `#__wrap`
and confirm those subjects are 100% under mutant.

**Likely files:** `lib/odata_duty/create_complex_type_hash_wrapper.rb`, `.mutant.yml`, new specs
under both spec trees.

**PRD excerpt (done):** POST `{id, address:{street, postcode:immutable}}` → `input.address.postcode
== "AB1"`; PATCH `{address:{street:"New", postcode:"XY9"}}` → `input.address.street == "New"`,
`input.address.postcode == nil`. "Nested dropped value → no error, reads back as `nil`." "Nested
wrong-typed value on a writable property → `OdataDuty::InvalidType`, unchanged."

**Depends on:** none (independent subjects; keep code edits from Task 2 in mind — same file).

- [ ] Done

## Task 4 — New `doc/using_context.md` + CLAUDE.md Features index

**Text:** Add `doc/using_context.md` documenting the context object: delegation to the caller's
`context:`, `od_full_url`, `query_options` normalization, `base_url`, `current`. Do **not** document
`context.endpoint` (internal). Add a one-line entry to the `## Features` index in `CLAUDE.md`
pointing at the new guide.

**Likely files:** `doc/using_context.md` (new), `CLAUDE.md`.

**PRD excerpt (done):** Documentation impact — "New `doc/using_context.md` … Add to the CLAUDE.md
Features index."

**Depends on:** Task 1 (pinned behavior it documents).

- [ ] Done

## Task 5 — Extend mutability & create/update docs

**Text:** Extend `doc/using_mutability.md` with a short "Nested complex types" section (mutability
applies to nested complex values; silent-drop semantics). Extend
`doc/using_create_update_and_delete.md` with the accessor-with-args error case
(`input.first_name('x')` → `NoSuchPropertyError`).

**Likely files:** `doc/using_mutability.md`, `doc/using_create_update_and_delete.md`.

**PRD excerpt (done):** Documentation impact — "Extend `doc/using_mutability.md` — a short 'Nested
complex types' section"; "Extend `doc/using_create_update_and_delete.md` — the accessor-with-args
error case."

**Depends on:** Tasks 2, 3 (behavior documented).

- [ ] Done
