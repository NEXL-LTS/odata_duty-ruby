# Build plan — Retire the `Executor` mutation-testing debt

PRD: [task-thwqmhclhhy3JKyD8d.md](./task-thwqmhclhhy3JKyD8d.md)

## Goal

Remove all 24 `OdataDuty::Executor#*` entries from `.mutant.yml`'s ignore list by pinning the
request-execution contract as spec-asserted public behavior, exercised through
`schema.execute` / `.create` / `.update` / `.delete` in **both** DSLs. Pure pin — no output or
error-message changes. Specs are described under the existing `OdataDuty::EntitySet` /
`OdataDuty::SchemaBuilder::EntitySet` constants — **never** `RSpec.describe OdataDuty::Executor`
(that would collapse mutant's full-suite fallback and strand 1357 kills).

## Per-task rules (bake into every subagent)

- TDD, public API only, both DSLs + both spec trees, 99-char lines, RuboCop metrics.
- Each task **removes its own subset of ignore entries** from `.mutant.yml` and verifies
  `bundle exec mutant run '<its subjects>'` reports **zero alive** (accept an equivalent
  mutation by simplifying `lib/` where tests agree — e.g. regex anchor `^`→`\A`, `$`→`\z`,
  `send`→`__send__`, slice bounds).
- Finish each task on a green `bundle exec rake`.
- Any `lib/odata_duty/executor.rb` change is a pure simplification (byte-identical behavior);
  the gemspec patch bump for all such changes lands once in the final task.

## Tasks

### - [x] Task 1 — Write-gating messages & endpoint resolution
Subjects (remove entries): `#create`, `#update`, `#delete`, `#endpoint`, `#urls`.
Pin, in both trees, on a schema with ≥2 sets where one set's resolver implements neither
create/update/delete: the exact `NoImplementationError` messages
`create not implemented for <url>`, `update not implemented for <url>`,
`delete not implemented for <url>`; the exact DELETE success envelope
`{"@odata.context":"<base>/$metadata"}` on a full-CRUD set; and the unknown-endpoint
`UnknownPropertyError` message `No endpoint <url> found in [<every set url>]` naming the full
URL list. PRD contract items 1, 5, 7 (delete envelope); "Behavior & expected I/O".
Files: `spec/odata_duty/entity_set/*` + `spec/odata_duty/schema_builder/entity_set/*` (new
`write_gating_spec.rb` / extend `read_path_contracts`), `.mutant.yml`.

### - [x] Task 2 — Key extraction
Subjects (remove entries): `#extract_value_from_brackets`.
Pin, in both trees, on a full-CRUD set with a `String` key, that `People('bob')`,
`People("bob")` and `People(bob)` resolve the same entity across GET/PATCH/DELETE, and interior
quotes are preserved (`People('it''s')` → key `it''s`). Expect an accepted residue of regex
anchor tightening (`^`→`\A`, `$`→`\z`) in `lib`. PRD contract item 2.
Files: entity_set + schema_builder/entity_set new `key_extraction_spec.rb`, `.mutant.yml`,
maybe `lib/odata_duty/executor.rb`.

### - [x] Task 3 — `$select` parsing & `od_select` payload
Subjects (remove entries): `#selected`, `#valid_selected`, `#execute`, `#apply_select`.
Pin, in both trees: whitespace tolerance (`$select=first_name, last_name` → 200); malformed
name → `InvalidQueryOptionError` `The property '<p>' is not valid`; undeclared name →
`UnknownPropertyError` `The property '<p>' does not exist`; both errors' first backtrace entry
is the entity type's definition location; and a resolver that **captures** its `od_select`
argument sees the full property list without `$select`, and selected + property-ref names
deduplicated with `$select`. Prefer capture-in-resolver over `expect_any_instance_of`. PRD
contract items 3, 4.
Files: extend `select_spec.rb` both trees + new `od_select_payload` coverage, `.mutant.yml`.

### - [x] Task 4 — `$filter` guards
Subjects (remove entries): `#assert_filter_valid_for_property`, `#_filter`, `#filter_value`.
Pin, in both trees: `$filter` on an undeclared property → `UnknownPropertyError`
`No such property <name>`; a non-collection op on a collection property →
`InvalidQueryOptionError` `Cannot apply '<op>' to a collection property '<name>'.`; a
collection op that succeeds on a collection property; an op with no matching `od_filter_*` hook
→ `NoImplementationError` `<property> <op> not supported`; and context-dependent
`filter_convert` coercion reaching the hook. PRD contract item 8.
Files: extend `filter_validation_spec.rb` (entity) / builder equivalent + `filter_date_coercion`,
`.mutant.yml`.

### - [x] Task 5 — Query-option gating truth table
Subjects (remove entries): `#apply_top`, `#apply_skip`, `#apply_skiptoken`, `#apply_search`.
Pin, in both trees, the truth table for each of `$top`/`$skip`/`$skiptoken`/`$search`: option
absent + hook absent → no raise; option absent + hook present → hook not called; option present
+ hook absent → `NoImplementationError` `<$option> not implemented for <ResolverClass>`; option
present + hook present → hook applied. Non-`$` query options ignored. PRD contract item 6.
Files: extend `executor_coverage_spec.rb` (entity) + new builder equivalent, `.mutant.yml`.

### - [x] Task 6 — `$count` / nextLink & plumbing residue
Subjects (remove entries): `#collection`, `#add_next_link`, `#initialize`, `#apply_remaining`,
`#individual`, `#prepare_builder`, `#wrapped_context`.
Pin, in both trees: `@odata.count` present iff `$count=true` exactly (`$count=1` → absent);
`@odata.nextLink` present iff resolver returns `od_next_link_skiptoken`, its URL built from the
set's own url and carrying original query options plus `$skiptoken`; query options applied on
individual requests; non-`$` options ignored. Accept plumbing residue case-by-case. PRD
contract item 7, "Plumbing residue" group.
Files: extend `collection_spec.rb` / paging specs both trees, `.mutant.yml`.

### - [ ] Task 7 — Docs, gemspec bump & final mutant verify
Optionally add one line naming the exact error messages to `doc/using_filter.md` and
`doc/using_select.md` (matching their "Common Error Cases" sections). If any `lib/` change
landed across Tasks 1–6, bump `spec.version` patch in `odata_duty.gemspec`. Confirm `.mutant.yml`
has zero `OdataDuty::Executor#*` entries left, then run `bundle exec mutant run
'OdataDuty::Executor*'` → **zero alive** and `bundle exec rake` green.
