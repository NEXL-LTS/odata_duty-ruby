# Build plan: Enforce public-API-only specs with a custom RuboCop cop

PRD: [doc/prds/public-api-only-cop.md](public-api-only-cop.md)

This PRD adds a single new RuboCop cop (`RuboCop::Cop::OdataDuty::PublicApiOnly`) that
scans `spec/**/*_spec.rb` for references to internal gem constants/methods, plus the
`.rubocop.yml` config that defines the public-API allowlist, plus the spec migrations
and docs the PRD requires. There is no consumer-facing DSL change (the cop is
contributor tooling), so the "both DSLs" rule from `CLAUDE.md` does not apply to new
production surface — but the *spec migrations* the cop forces do touch files under both
`spec/odata_duty/entity_set/**` (search_spec.rb, select_spec.rb) and no schema_builder
files (neither offending spec lives in that tree). No schema_builder equivalent of
search_spec.rb/select_spec.rb needs migration because the PRD's audit found the five
offences only in the entity_set tree.

## Task 1 — Cop skeleton with the internal-constant check, config wiring, and cop spec

**Task text:** Create `rubocop/cop/odata_duty/public_api_only.rb` implementing
`RuboCop::Cop::OdataDuty::PublicApiOnly < RuboCop::Cop::Base`, covering only the
**internal constant** check for this task: a constant node whose full path starts with
`OdataDuty::` and is neither in `AllowedConstants` nor matched by
`AllowedConstantPatterns` is flagged, checking only the outermost const node (so
`OdataDuty::Schema::Metadata` reports once, not twice). Wire `.rubocop.yml`: add the
`require:` pointing at the cop file (relative `./rubocop/...` form), and the
`OdataDuty/PublicApiOnly` config block with `Enabled: true`, `Namespace: OdataDuty`,
`Include: ['spec/**/*_spec.rb']`, the full `AllowedConstants` list, and
`AllowedConstantPatterns` (both regexes). Create `spec/rubocop/public_api_only_spec.rb`
using `rubocop/rspec/support` (require it plus `RuboCop::RSpec::ExpectOffense`), covering
at minimum: an allowlisted constant (accepted), a constant matched by each of the two
patterns (accepted), an internal constant (flagged, with the exact message wording from
the PRD), a nested constant under an allowlisted parent (flagged once, not twice — needs
examples for: top-level constant with nil parent, a constant whose parent is not itself a
const node, a nested constant where the guard is taken, and an allowed constant that
falls through the guard), and a `cop_config` with no `Namespace` key exercising the
`fetch` default. Do NOT yet implement the other three checks (method-prefix, bypass,
mocking) — those are later tasks. `bundle exec rake` must be green, and this task's new
file must sit at 100% line+branch coverage on its own (SimpleCov tracks it from this
spec's first example onward per the PRD).

**Definition of done (PRD excerpt):**
- Config block (PRD "Configuration" section, verbatim YAML).
- Check table row: "Internal constant | A constant node whose full path starts with
  `OdataDuty::` and is neither in `AllowedConstants` nor matched by
  `AllowedConstantPatterns` | Outermost const only, so `OdataDuty::Schema::Metadata`
  reports once".
- Message: `` `OdataDuty::Executor` is not part of the public API. Specs must exercise
  the gem through its documented surface. ``
- Coverage-safety notes (PRD "Coverage and mutation testing"): `@allowed_constants ||=
  Set.new(...)` and `cop_config.fetch('Namespace', 'OdataDuty')` need no `defined?`
  rework; the outermost-const guard `return if node.parent&.const_type?` needs four
  covered arms (top-level/nil parent, non-const parent, nested/guard-taken, allowed
  constant falls through).
- Cop spec minimum list (PRD "Cop spec" section) — only the constant-related bullets
  apply to this task: allowlisted constant accepted; constant matched by each pattern
  accepted; internal constant flagged; nested constant flagged once not twice;
  `cop_config` with no `Namespace` key.
- Failure mode: "Missing cop file" — wrong `require:` path fails to load; relative
  `./rubocop/...` form is required to resolve from repo root. Add a spec/manual check
  that the `require:` path in `.rubocop.yml` is correct (verified by `bundle exec
  rubocop` itself loading successfully in this task's manual verification, since a spec
  can't easily assert on `.rubocop.yml` loading without invoking the CLI).

**Likely files:** `rubocop/cop/odata_duty/public_api_only.rb` (new),
`spec/rubocop/public_api_only_spec.rb` (new), `.rubocop.yml` (edit).

**Depends on:** nothing (first task).

- [ ]

## Task 2 — `__`-prefixed internal-method check

**Task text:** Extend the cop with the second independent check: any `send`/`csend` node
whose method name starts with `__` is flagged, regardless of receiver (receiver-agnostic
— must fire on `foo.__metadata`, `__metadata` with implicit receiver, etc., using the
exact message wording). Add cop-spec examples per the PRD's minimum list: a
`__`-prefixed method call flagged regardless of receiver. Also add the "Flagging
`__send__` twice" failure-mode guard from the PRD: `__send__` is both a bypass method
(task 3) and `__`-prefixed, but for *this* task, make sure the check only reports once
per node even though it will later also be checked by the bypass-method check (do this by
using `add_offense` once per node per distinct violation type as separate offenses is
fine per PRD wording "it must report once" — read the PRD's failure-mode bullet
carefully: it says `__send__` must report once overall, which the final task (task 3,
combining bypass-check) must guarantee via an early-return / elsif chain, not this task in
isolation). For now this task only needs its own check correct and covered; task 3 will
verify the combined single-report behavior for `__send__` specifically.

**Definition of done (PRD excerpt):**
- Check table row: "Internal method | A send/csend whose method name starts with `__` |
  Receiver-agnostic".
- Message: `` `__metadata` is an internal method (`__` prefix). Specs must exercise the
  gem through its documented surface. ``
- Offence example: `schema.__metadata.entity_sets` flagged on `__metadata`.
- Accepted example: none specific to this check beyond not flagging non-`__` methods.
- Cop-spec bullet: "a `__`-prefixed method call, flagged regardless of receiver".

**Likely files:** `rubocop/cop/odata_duty/public_api_only.rb`,
`spec/rubocop/public_api_only_spec.rb`.

**Depends on:** Task 1 (cop skeleton must exist).

- [ ]

## Task 3 — Visibility-bypass and mocking-behaviour checks (with `__send__`/`public_send` edge cases)

**Task text:** Add the two remaining independent checks to the same cop:
(a) **Visibility bypass** — a send/csend whose method name is one of `send`,
`__send__`, `instance_variable_get`, `instance_variable_set`, `instance_eval`,
`const_get`, `method`, on any receiver, flagged with the bypass message naming the
method. `public_send` must NOT be flagged (explicit negative case). (b) **Mocking gem
behaviour** — a send/csend whose method name is one of `expect_any_instance_of`,
`allow_any_instance_of`, `stub_const`, on any receiver, flagged with the mocking
message naming the method. Critically, `__send__` is both `__`-prefixed (task 2's check)
and a bypass method (this task's check) — the cop must report it exactly **once**, not
twice; pick one check to take priority (the PRD doesn't say which — bypass-message
wording ("`send` bypasses...") reads more specifically for `__send__` than the generic
`__`-prefix message, so prefer reporting it as a bypass) and structure the method-name
dispatch (e.g. a single `on_send`/`on_csend` handler with an early-return chain or a
`case` over method name, checking bypass/mocking lists before falling through to the
generic `__`-prefix check) so only one offense is ever added per node. Add cop-spec
examples: each bypass method flagged (send, __send__, instance_variable_get,
instance_variable_set, instance_eval, const_get, method), `public_send` accepted, each
mocking method flagged (expect_any_instance_of, allow_any_instance_of, stub_const), and
a dedicated example asserting `__send__` produces exactly one offense (not two).

**Definition of done (PRD excerpt):**
- Check table rows: "Visibility bypass | `send`, `__send__`, `instance_variable_get`,
  `instance_variable_set`, `instance_eval`, `const_get`, `method` | Any receiver" and
  "Mocking gem behaviour | `expect_any_instance_of`, `allow_any_instance_of`,
  `stub_const` | Any receiver".
- Messages: `` `send` bypasses method visibility. Specs must exercise the gem through
  its documented surface. `` and `` `expect_any_instance_of` mocks gem behaviour. Specs
  must assert on the gem's output instead. ``
- "`public_send` is deliberately **not** a bypass" — explicit accepted example:
  `record.public_send(property_name)`.
- "`const_get` being flagged is what closes the obvious hole" —
  `Object.const_get('OdataDuty::Executor')` must be flagged as a bypass.
- Failure mode: "Flagging `__send__` twice. It is both a bypass method and
  `__`-prefixed; it must report once."
- Cop-spec bullets: "each bypass method, flagged"; "`public_send`, accepted"; "each
  mocking method, flagged".

**Likely files:** `rubocop/cop/odata_duty/public_api_only.rb`,
`spec/rubocop/public_api_only_spec.rb`.

**Depends on:** Task 2 (the `__`-prefix check must exist to create the `__send__`
overlap this task resolves).

- [ ]

## Task 4 — RuboCop metrics/lint pass and full-suite `bundle exec rake` on the cop alone

**Task text:** With all four checks implemented (tasks 1–3), run `bundle exec rubocop`
against `rubocop/cop/odata_duty/public_api_only.rb` itself (nothing in
`AllCops.Exclude` covers `rubocop/`, so it is linted like any other file) and fix any
metric violations (MethodLength 13, AbcSize 30, 99-char lines) by extracting helper
methods rather than adding inline disables. Run `bundle exec rake` and confirm the new
cop file plus its spec sit at 100% line+branch coverage in the SimpleCov report (no
`add_filter` for `rubocop/` exists or should be added). This task is a checkpoint/cleanup
task, not new checks — if tasks 1–3 already leave the cop clean and covered, this task
folds into verifying that and making minor extractions only if needed. Do not turn on the
`.rubocop.yml` cop against the full spec suite's offences yet — that happens in tasks 5–6
which fix the offences first, to avoid a red intermediate state if done out of order (in
practice, since the cop's `Include` is already spec/**/*_spec.rb from task 1, running
`bundle exec rubocop` project-wide from here on will show the 5 real offences until tasks
5–6 land; that is expected and should be verified now so the next tasks know exactly what
to fix).

**Definition of done (PRD excerpt):**
- "The cop file itself is linted by RuboCop... it must satisfy the repo's tightened
  metrics: `MethodLength` 13, `AbcSize` 30, 99-char lines, no inline disables."
- "held to the same bar as `lib/`: SimpleCov's 100% line and branch enforcement
  applies, with **no** `add_filter` for `rubocop/`."
- Confirm via `bundle exec rubocop` output that it currently reports exactly the offences
  described in "Migrating the existing suite" (1 in search_spec.rb, 4 in select_spec.rb)
  and nothing else spurious.

**Likely files:** `rubocop/cop/odata_duty/public_api_only.rb` (possible refactor only).

**Depends on:** Task 3.

- [ ]

## Task 5 — Migrate `select_spec.rb`'s four `expect_any_instance_of` offences

**Task text:** In `spec/odata_duty/entity_set/select_spec.rb`, replace the four
`expect_any_instance_of(SupportsCollectionSelectSet).to receive(:od_select)...` examples
(lines ~151, 167, 241, 259) using the capture-fixture pattern that already exists in the
same file (`CapturingSelectSet`, lines ~60–86, with its `captured_select`
class-level accessor). For each of the four mocked examples: either convert it to assert
on `CapturingSelectSet.captured_select` (mirroring the existing "passes selected names
plus refs..." examples at the bottom of the file) or delete it if the existing
`CapturingSelectSet` examples already cover the exact same assertion (both the
individual-fetch and collection-fetch `$select` capture cases). Since `select_spec.rb` is
entity_set (class DSL) only, check whether
`spec/odata_duty/schema_builder/**` has an equivalent file with the same
`expect_any_instance_of` pattern for `$select` — if so, migrate it identically; if no
such offence exists there (per the PRD's audit table, only entity_set has these), state
so explicitly and do not add unrelated changes to that tree. After the change,
`spec/odata_duty/entity_set/select_spec.rb` must have zero `expect_any_instance_of`
occurrences, and existing/replacement examples must still assert the same observable
behavior (the resolved `od_select` list, and the same JSON output shape) so nothing about
the feature's documentation value is lost.

**Definition of done (PRD excerpt):**
- "Migrating the existing suite" item 2: four `expect_any_instance_of` uses in
  `select_spec.rb` (lines 151, 167, 241, 259), each `expect_any_instance_of(...).to
  receive(:od_select).with(%i[...]).and_call_original`.
- "The replacement pattern **already exists in the same file**: `CapturingSelectSet`
  (line 60) records what the framework passed it, and lines 342–349 assert on that
  recording" — with the exact example shown in the PRD (`captured_select` assertions).
- "Each of the four mocked examples is either converted to this capture-fixture pattern
  or deleted where the existing `CapturingSelectSet` examples already cover the same
  assertion."
- "This is strictly better documentation: the fixture shows a consumer what their
  `od_select`... implementation actually receives, instead of a mock asserting it from
  outside."

**Likely files:** `spec/odata_duty/entity_set/select_spec.rb`. Check (read-only, no
changes expected) `spec/odata_duty/schema_builder/**` for an equivalent select spec.

**Depends on:** Task 4 (cop is fully implemented and reporting the real offences to fix
against).

- [ ]

## Task 6 — Migrate `search_spec.rb`'s constant+mock offence and promote `SearchExpression`/`SearchTerm` to the allowlist

**Task text:** In `spec/odata_duty/entity_set/search_spec.rb`, replace the single
offending example (~line 155–161, `it 'calls od_search method when implemented'` using
`expect_any_instance_of(SupportsCollectionSearchSet).to
receive(:od_search).with(instance_of(OdataDuty::SearchExpression)).and_call_original`)
with an equivalent capture-fixture: extend `SupportsCollectionSearchSet` (or add a
sibling capturing set, following the `CapturingSelectSet` precedent from task 5) to
record the `SearchExpression` it received, then assert on the documented surface —
`expression.terms` and `expression.or?`/`and?` — rather than asserting on the object's
class via `instance_of`. `OdataDuty::SearchExpression` is already referenced elsewhere in
this same file's non-mock examples (e.g. via `od_search(search_expression)` in the
existing `SupportsCollectionSearchSet#od_search` definition) — confirm those references
are fine once `OdataDuty::SearchExpression` and `OdataDuty::SearchTerm` are on the
`AllowedConstants` list added in task 1 (they should already be listed there per this
plan's task 1 — verify, don't re-add). Check
`spec/odata_duty/schema_builder/**` for an equivalent `$search` spec with the same
constant+mock pattern; per the PRD's audit this offence exists only in the entity_set
tree, but confirm and migrate identically if found. After this task, `bundle exec
rubocop` must report **zero** offences for `OdataDuty/PublicApiOnly` across the whole
`spec/` tree — this is the task that brings the suite fully green under the new cop.

**Definition of done (PRD excerpt):**
- "Migrating the existing suite" item 1: `spec/odata_duty/entity_set/search_spec.rb:157`
  — "This is both a constant reference and a mock. `OdataDuty::SearchExpression` moves
  to the allowlist (it is documented API), but the mock still has to go."
- "The search-spec case (1) gets an equivalent capturing set that records the
  `SearchExpression` it received; the example then asserts on `expression.terms` and
  `expression.or?` — the documented surface — rather than on the object's class."
- "Nothing else. No `send`, `__send__`, `instance_variable_get`, `const_get`,
  `instance_eval`, `stub_const`, or `__`-prefixed call exists in any `*_spec.rb` today"
  — i.e., after tasks 5+6, the migration is complete; no further offences remain.
- Accepted example from PRD: `def od_search(expression) = expression.terms         #
  SearchExpression allowlisted`.

**Likely files:** `spec/odata_duty/entity_set/search_spec.rb`. Check (read-only)
`spec/odata_duty/schema_builder/**` for an equivalent search spec.

**Depends on:** Task 5 (keeps the two migration tasks independent/reviewable, but ordered
so the final full-suite-green check happens once, at the end of this task).

- [ ]

## Task 7 — Documentation: new `spec/using_public_api_only.md`, move `doc/using_coverage.md` → `spec/using_coverage.md`, update `CLAUDE.md` and `doc/using_search.md`

**Task text:** (a) Create `spec/using_public_api_only.md`, a contributor guide styled
like `spec/using_mutant.md`: explain what the cop enforces (the four checks), what the
`AllowedConstants`/`AllowedConstantPatterns` allowlist in `.rubocop.yml` means and how it
maps to the README's public-API groups, how to respond to each of the four offense
messages (fix by using the documented surface, or extend the allowlist as a reviewed
contract change), and the rule that widening the allowlist requires a corresponding
`doc/using_*.md` update. (b) Move `doc/using_coverage.md` to `spec/using_coverage.md`
(`git mv`), and update every reference: `CLAUDE.md`'s `bundle exec rake` bullet (currently
pointing at `doc/using_coverage.md`), `spec/using_mutant.md`'s reference to
`doc/using_coverage.md`, and any other repo reference found by grep (e.g. README.md, if
any). (c) Update `CLAUDE.md`: the "Tests must use only the gem's public API" bullet gains
a pointer to the new cop and to `spec/using_public_api_only.md`; the "Tests are public
documentation" bullet's "No stubbing (`stub_const`, mocks) of gem internals" line should
say this is now enforced (by the cop), not just advisory. (d) Update
`doc/using_search.md` with a short note pinning `SearchExpression`/`SearchTerm` as public
API, listing `.terms`, `.or?`, `term.value`, `term.not?` as the methods a consumer may
rely on, noting the RuboCop allowlist now makes this a formal commitment.

**Definition of done (PRD excerpt):**
- "Documentation impact" section, all four bullets verbatim:
  - "**New: `spec/using_public_api_only.md`**... what the cop enforces, what the
    allowlist means, how to respond to each of the four messages, and the rule that
    widening the allowlist is a contract change requiring a `doc/using_*.md` update."
  - "**Move: `doc/using_coverage.md` → `spec/using_coverage.md`**... Update the two
    references: `CLAUDE.md:29` and `spec/using_mutant.md:6`."
  - "**Update `CLAUDE.md`:** The 'Tests must use only the gem's public API' convention
    bullet gains a pointer to the cop and to `spec/using_public_api_only.md`. The 'Tests
    are public documentation' bullet's 'No stubbing...' becomes enforced rather than
    advisory, and should say so. The `bundle exec rake` command bullet's
    `doc/using_coverage.md` reference becomes `spec/using_coverage.md`."
  - "**Update `doc/using_search.md`** — a short note pinning `SearchExpression` and
    `SearchTerm` as public API, listing the methods a consumer may rely on (`.terms`,
    `.or?`, `term.value`, `term.not?`)."

**Likely files:** `spec/using_public_api_only.md` (new), `doc/using_coverage.md` →
`spec/using_coverage.md` (moved), `CLAUDE.md`, `spec/using_mutant.md`,
`doc/using_search.md`. No `lib/` changes.

**Depends on:** Task 6 (docs should describe the cop's final, fully-migrated behavior).

- [ ]
