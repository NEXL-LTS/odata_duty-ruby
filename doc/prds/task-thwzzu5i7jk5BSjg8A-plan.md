# Build plan — Retire the `$search` parser mutation-testing debt

PRD: [task-thwzzu5i7jk5BSjg8A.md](./task-thwzzu5i7jk5BSjg8A.md)

Goal: remove the 7 `OdataDuty::SearchExpression*` / `OdataDuty::SearchTerm*` entries from
`.mutant.yml`'s ignore list by pinning the `$search` parsing contract as spec-asserted public
behavior in **both** DSL spec trees, plus accept-mutation simplifications inside the parser where
the surviving mutant is the simpler, behavior-identical code. No output changes — a pure pin.

Verification of the whole PRD: `bundle exec mutant run 'OdataDuty::SearchExpression*'
'OdataDuty::SearchTerm*'` shows **zero alive**, and `bundle exec rake` stays green.

---

## Task 1 — Pin the `$search` contract with public-API specs in both spec trees

**Status:** - [x]

**Task text:** Add public-API specs to **both** `spec/odata_duty/entity_set/search_spec.rb` and
`spec/odata_duty/schema_builder/entity_set/search_spec.rb` that pin the currently-unasserted
`$search` behavior a resolver's `od_search` observes and the errors malformed input raises. The
search set/resolver in each tree must capture the `SearchExpression` it receives (its `terms`,
`and?`, `or?`) and each term's `to_s`, exposed via a public class-level accessor (the class DSL
already does this with `last_rendered_terms` — extend that pattern; add an equivalent to the
builder-DSL resolver). Assert, per the PRD's request→observation table:

- `$search=` (empty) and `$search=` of only whitespace (`'   '`) → `od_search` is called with an
  expression whose `terms == []`, `and? == true`, `or? == false`.
- `$search=a OR b` → the received expression has `or? == true` **and `and? == false`**; for a
  single term, implicit AND, and explicit AND, `and? == true` **and `or? == false`** (pin the
  false side of each flag — that is what keeps `#and?` alive).
- `$search=(hello` (only `(`) and `$search=hello)` (only `)`) → `NoImplementationError`, message
  `Parentheses are not supported`.
- `$search=hello AND foo!` (unparseable, contains ` AND ` but not ` OR `) and
  `$search=foo! OR hello` (unparseable, contains ` OR ` but not ` AND `) → `InvalidQueryOptionError`,
  message starting `Invalid search expression: `.
- `$search=a AND OR AND b` (explicit-AND tree containing the word `OR`) → `NoImplementationError`,
  message `Mixed AND/OR operators are not supported`.
- `$search=NOT "old data" AND hello` → the received terms render via `to_s` as `NOT "old data"`
  and `hello`.
- Surrounding whitespace tolerance: `$search=  hello  ` behaves exactly like `$search=hello`.

Tests use the gem's **public API only** (`schema.execute` + a resolver-observed accessor). This
task is test-only — `bundle exec rake` stays green; the `.mutant.yml` entries are removed in Task 2.

**Likely files:** `spec/odata_duty/entity_set/search_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/search_spec.rb`.

**PRD excerpt (definition of done):** the "The pinned contract", "Behavior & expected I/O" table,
and "Common error cases" sections. Discriminating detail: unparseable inputs containing only one
of ` AND `/` OR ` must raise `InvalidQueryOptionError` (the fallback), not the mixed-operator
`NoImplementationError`.

**Depends on:** nothing.

---

## Task 2 — Accept-mutation parser simplifications, remove the 7 ignore entries, gemspec bump

**Status:** - [x]

**Task text:** With Task 1's pins in place, apply the accept-mutation simplifications in
`lib/odata_duty/parslet_search_expression.rb` where the surviving mutant is the simpler,
behavior-identical code, then delete the 7 `OdataDuty::SearchExpression*` /
`OdataDuty::SearchTerm*` entries from `.mutant.yml`'s ignore list and bump the gemspec patch
version. Candidates from the PRD (verify each against mutant, keep whichever form mutant accepts):

- `.parse`'s `nil` guard — no public path passes `nil`; restructure so the equivalent
  `strip`/`lstrip`/`rstrip` mutants no longer exist (the grammar already tolerates surrounding
  whitespace; the empty/whitespace pin from Task 1 guards the empty case).
- `SearchExpression#initialize`'s `Array(terms)` → `@terms = terms`.
- `SearchTerm#initialize`'s `negated: false` default — make required (or whatever mutant accepts).
- `SearchTerm#to_s`'s `else ''` branch → `prefix = ('NOT ' if @negated)`.
- `.validate_parse_tree`'s `.to_s` — possibly equivalent (Parslet slice `==`); verify with the
  `a AND OR AND b` spec present and accept only if truly equivalent, else leave and let a spec
  cover it.

Every accept must leave the request→observation table green. Run
`bundle exec mutant run 'OdataDuty::SearchExpression*' 'OdataDuty::SearchTerm*'` and confirm
**zero alive** before finishing. Keep `bundle exec rake` green. Keep methods within RuboCop
metrics — no gratuitous disables. Bump `spec.version` in `odata_duty.gemspec` by a patch level.

**Likely files:** `lib/odata_duty/parslet_search_expression.rb`, `.mutant.yml`,
`odata_duty.gemspec`.

**PRD excerpt (definition of done):** the yaml block of 7 entries, "Accept-mutation candidates"
section, and "Verification" bullet in Scope.

**Depends on:** Task 1 (the pins must exist so the only survivors left are the accept candidates).

---

## Task 3 — Fix the `doc/using_search.md` error-contract drift

**Status:** - [x]

**Task text:** In `doc/using_search.md`, fix the intro line that says a missing `od_search` raises
`InvalidQueryOptionError` — the code and the guide's own "Common Error Cases" section say
`NoImplementationError`. Correct the intro to `NoImplementationError`. Confirm the `## Features`
`$search` entry in `CLAUDE.md` still points at this guide (no new capability is added, so no index
change is expected; note it if one is). Docs-only — `bundle exec rake` stays green.

**Likely files:** `doc/using_search.md`, (verify only) `CLAUDE.md`.

**PRD excerpt (definition of done):** "Documentation impact" section — the known drift is the
intro line claiming `InvalidQueryOptionError` for a missing `od_search`.

**Depends on:** nothing (independent), sequenced last.
