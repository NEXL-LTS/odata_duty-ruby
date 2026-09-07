# Build plan: Reject invalid `$top`/`$skip` values

PRD: [doc/prds/top-skip-negative-validation.md](top-skip-negative-validation.md)

## Task 1: Validate `$top`/`$skip` in `Executor` before dispatch

- [x] Status

**Task text:** In `lib/odata_duty/executor.rb`, add validation of the raw `$top` and `$skip`
query-option string values, applied before the existing `respond_to?(:od_top)`/`respond_to?(:od_skip)`
support check and before either hook is invoked. A value is valid iff it is parseable as a base-10
integer (`Integer(value, 10)`, rejecting `0x`/`0o`/`0b` prefixes and any exponent/decimal-point
input — but `'010'` must parse as decimal `10`, not be rejected and not be misread as octal `8`) and
the resulting integer is `>= 0`. On an invalid value, raise `OdataDuty::InvalidQueryOptionError` with
message `"'$top' must be a non-negative integer, got '<value>'"` (or `'$skip'` for skip), immediately
— `od_top`/`od_skip` and the `NoImplementationError` check must never run for that request. `nil`/
absent `$top` or `$skip` is unaffected (no validation, no hook call, exactly as today). A *valid*
`$top`/`$skip` on an entity set that doesn't implement the corresponding hook must still raise
`NoImplementationError`, unchanged. This is one shared change in `Executor`, exercised identically by
both DSLs since `EntitySet` and `SetResolver` both dispatch through it — add matching tests to
**both** spec trees.

**Definition of done (PRD excerpt — Validation contract, Behavior & expected I/O, Common error cases):**

```
- Applies to the raw `$top` and `$skip` query-option string, before `od_top`/`od_skip` support is
  checked and before either hook is invoked.
- A value is valid if and only if it is parseable as a base-10 integer (`Integer(value, 10)`,
  disallowing `0x`/`0o`/`0b` prefixes and octal-by-leading-zero misreads — `'010'` is decimal `10`,
  not octal `8`) and the resulting integer is `>= 0`.
- `nil`/absent `$top` or `$skip` (the option wasn't supplied) is unaffected — no validation runs
  and no hook is called, exactly as today.
- On an invalid value, OdataDuty raises `InvalidQueryOptionError` immediately — `od_top`/`od_skip`
  (and the `NoImplementationError` check for entity sets that don't implement them) are never
  reached for that request.
```

Error cases to cover, each raising `OdataDuty::InvalidQueryOptionError` with the exact message shown:

- `$top=-1` / `$skip=-1` → `"'$top' must be a non-negative integer, got '-1'"` / `"'$skip' must be a non-negative integer, got '-1'"`
- `$top=abc` → `"'$top' must be a non-negative integer, got 'abc'"`
- `$top=1.5` → `"'$top' must be a non-negative integer, got '1.5'"`
- `$top=` (empty string) → `"'$top' must be a non-negative integer, got ''"`

Must remain valid and unchanged (still call the hook with the original string):

- `$top=010` → valid, parsed as decimal `10`, `od_top('010')` called (not misread as octal `8`)
- `$top=0` / `$skip=0` → valid, hook called with `'0'`
- `$top=25&$skip=0` → both hooks called
- A *valid* `$top`/`$skip` on a set without `od_top`/`od_skip` still raises `NoImplementationError`
  (`"$top not implemented for #{set_builder.class}"` / `"$skip not implemented for..."`), unchanged.

**Likely files:**
- `lib/odata_duty/executor.rb` (`apply_top`, `apply_skip`, plus a shared private validation helper —
  this is the only production file; both DSLs share this one `Executor`).
- `spec/odata_duty/entity_set/collection_spec.rb` and/or `spec/odata_duty/entity_set/executor_coverage_spec.rb`
  (class DSL, `OdataDuty::EntitySet` / `LargeCollectionSet` / `ExecCovSet` style fixtures).
- `spec/odata_duty/schema_builder/entity_set/collection_spec.rb` and/or
  `spec/odata_duty/schema_builder/entity_set/executor_query_option_gating_spec.rb` (builder DSL,
  `OdataDuty::SetResolver` fixtures).

State explicitly in the implementer report whether one or both DSL spec trees were touched, and why
(the validation itself is one shared code path, but both spec trees are existing regression points
for `$top`/`$skip` per repo convention, e.g. `spec/odata_duty/entity_set/executor_coverage_spec.rb`
and `spec/odata_duty/schema_builder/entity_set/executor_query_option_gating_spec.rb` already carry
parallel "raises the exact message for $top when od_top is absent" tests for each DSL).

**Dependencies:** none (first task).

## Task 2: Add `doc/using_paging.md` guide and update the `AGENTS.md`/`CLAUDE.md` Paging index entry

- [ ] Status

**Task text:** Add a new guide `doc/using_paging.md`, in the same style as `doc/using_filter.md` and
`doc/using_select.md` (Overview / Implementing the hooks / example implementations for both DSLs /
Common Error Cases / Summary), covering `$top`, `$skip`, `$skiptoken`, and server-driven
`@odata.nextLink` via `od_next_link_skiptoken` together — these currently have no dedicated guide
(only a one-line mention in `doc/odata_crash_course.md` and usage shown solely in specs). Include the
new validation behavior from Task 1 and its exact error cases in this guide. Then update the existing
`## Features` **Paging** bullet in `AGENTS.md` (currently guide-less; `CLAUDE.md` is a symlink to
`AGENTS.md` so it updates automatically) to link to the new guide and mention the validation, per
`doc/conventions/doc-guides.md`.

**Definition of done (PRD excerpt — Documentation impact):**

```
Add a new guide, `doc/using_paging.md`, covering `$top`, `$skip`, `$skiptoken`, and
`@odata.nextLink` (`od_next_link_skiptoken`) together — these currently have no dedicated guide
(only a one-line mention in `doc/odata_crash_course.md` and usage shown solely in specs). Include
this validation behavior and its error cases in that guide, in the same style as
`doc/using_filter.md` and `doc/using_select.md`.

Per `doc/conventions/doc-guides.md` (one guide per feature, linked from the `AGENTS.md` index):
update the existing `AGENTS.md` **Paging** bullet (currently guide-less) to link to the new
`doc/using_paging.md`, e.g. `... via `od_next_link_skiptoken`; `$top`/`$skip` reject
negative or malformed values — `doc/using_paging.md`.` No `README.md` example currently
demonstrates `$top`/`$skip`, so no README change is needed.
```

Current `AGENTS.md` line 22 (to be replaced):
```
- **Paging** — `$top`/`$skip` and server-driven `@odata.nextLink` via `od_next_link_skiptoken`.
```

**Likely files:**
- `doc/using_paging.md` (new).
- `AGENTS.md` (line 22, `## Features` list; `CLAUDE.md` is a symlink, no separate edit needed).

No production code or spec changes in this task — documentation only, so `bundle exec rake` should
already be green from Task 1; this task's own gate is that `rake` stays green (RuboCop doesn't lint
`doc/`, but running `rake` confirms nothing broke).

**Dependencies:** Task 1 (the guide documents the validation behavior Task 1 implements, and must
describe real, already-implemented behavior — not aspirational).
