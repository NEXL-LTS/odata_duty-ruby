# Build plan — Enforce public-API-only specs with a custom RuboCop cop

PRD: [`public-api-only-cop.md`](./public-api-only-cop.md)

Controller-derived task plan. Each task is dispatched to a fresh implementer subagent, then
reviewed via `review-task` (spec compliance → code quality), then committed. One commit per task.

## Notes on decomposition

- **Task 1** creates the cop *and* its spec but does **not** wire it into `.rubocop.yml`. On its
  own this is fully green: `rake`'s RSpec run loads the cop via the cop spec (SimpleCov tracks it,
  100% line+branch required), and `rake`'s RuboCop run lints the cop file (tight metrics). The cop
  simply doesn't run over the suite yet, so no migration is needed to stay green.
- **Task 2** is a **jointly-green** task: enabling the cop in `.rubocop.yml` immediately flags the
  five existing offences, so enabling + migrating must be one commit or `rake` is red in between.
- **Task 3** is documentation only — no code, cannot break `rake`.
- **Features index**: this PRD adds contributor tooling, not a consumer-visible capability, so the
  `## Features` index in `CLAUDE.md` gets no new entry. The one contract change (publishing
  `SearchExpression`/`SearchTerm`) is captured in `doc/using_search.md` per Task 3.

## Tasks

### - [ ] Task 1 — The `OdataDuty/PublicApiOnly` cop + its spec

**Task text:** Create the RuboCop cop `RuboCop::Cop::OdataDuty::PublicApiOnly` at
`rubocop/cop/odata_duty/public_api_only.rb`, test-first, with its spec at
`spec/rubocop/public_api_only_spec.rb` using RuboCop's RSpec support
(`require 'rubocop/rspec/support'`). Do **not** wire the cop into `.rubocop.yml` in this task.
The cop performs four independent checks, each with its own message:

1. **Internal constant** — an `on_const` node whose full namespaced path starts with the
   configured `Namespace` (default `OdataDuty`, read via `cop_config.fetch('Namespace',
   'OdataDuty')`) and is neither in `AllowedConstants` nor matched by any `AllowedConstantPatterns`
   regexp. Report the **outermost** const only (guard `return if node.parent&.const_type?`) so
   `OdataDuty::Schema::Metadata` reports once, not twice. Message:
   `` `<const>` is not part of the public API. Specs must exercise the gem through its documented surface. ``
2. **Internal method** — an `on_send`/`on_csend` whose method name starts with `__`
   (receiver-agnostic). Message:
   `` `<method>` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface. ``
3. **Visibility bypass** — a send whose method is one of `send`, `__send__`,
   `instance_variable_get`, `instance_variable_set`, `instance_eval`, `const_get`, `method` (any
   receiver). `public_send` is **not** a bypass. `__send__` is both a bypass and `__`-prefixed and
   must report **once**. Message:
   `` `<method>` bypasses method visibility. Specs must exercise the gem through its documented surface. ``
4. **Mocking gem behaviour** — a send whose method is one of `expect_any_instance_of`,
   `allow_any_instance_of`, `stub_const` (any receiver). Message:
   `` `<method>` mocks gem behaviour. Specs must assert on the gem's output instead. ``

The cop must read config from `cop_config` (`Namespace`, `AllowedConstants`,
`AllowedConstantPatterns`), memoising with `||=` (coverage-safe; **not** `defined?`-guarded).
It must satisfy repo RuboCop metrics (`MethodLength` 13, `AbcSize` 30, `CyclomaticComplexity` 7,
99-char lines, **no inline disables**) and reach **100% line + branch** coverage under SimpleCov
(no `add_filter` for `rubocop/`). Carry no defensive/unreachable branches.

Cop spec must cover at minimum: an allowlisted constant accepted; a constant matched by each error
pattern accepted; an internal constant flagged; a nested constant under an allowlisted parent
flagged once not twice; a top-level constant (nil parent) and a const whose parent is not a const
(to cover all four arms of the `node.parent&.const_type?` guard); a `__`-prefixed call flagged
regardless of receiver; each bypass method flagged; `public_send` accepted; each mocking method
flagged; `__send__` flagged once; and a `cop_config` with no `Namespace` key exercising the default.
Use string/heredoc internal constant names in the spec source so the cop never flags its own spec.

**Likely files:** `rubocop/cop/odata_duty/public_api_only.rb` (new),
`spec/rubocop/public_api_only_spec.rb` (new). No DSL/`lib` change — this is tooling, so it touches
neither DSL nor either DSL spec tree.

**Defining PRD excerpt:** *External API → What the cop checks* (the four-check table),
*Behavior & expected I/O → Offences/Accepted*, *Common error cases* (four messages + the four
failure modes), *Coverage and mutation testing*, *Cop spec*.

**Depends on:** nothing.

### - [ ] Task 2 — Enable the cop in `.rubocop.yml` and migrate the five existing offences

**Task text:** Wire the cop into `.rubocop.yml` exactly as the PRD's *Configuration* block
specifies: `require: - ./rubocop/cop/odata_duty/public_api_only.rb`, and an `OdataDuty/PublicApiOnly`
section with `Enabled: true`, `Namespace: OdataDuty`, `Include: ['spec/**/*_spec.rb']`, the twelve
`AllowedConstants`, and the two `AllowedConstantPatterns`
(`\AOdataDuty::\w*Error\z` and `\AOdataDuty::Invalid\w+\z`). No `Exclude`. Then migrate the five
offences the cop now flags so `bundle exec rake` is green (this is a single jointly-green commit):

- `spec/odata_duty/entity_set/search_spec.rb:157` — the `expect_any_instance_of(...)
  .to receive(:od_search).with(instance_of(OdataDuty::SearchExpression))` example. Replace with a
  capturing entity-set fixture that records the `SearchExpression` its `od_search` receives; the
  example then asserts on the documented surface (`expression.terms`, `expression.or?`) rather than
  on the object's class or via a mock.
- `spec/odata_duty/entity_set/select_spec.rb` lines 151, 167, 241, 259 — the four
  `expect_any_instance_of(SupportsCollectionSelectSet).to receive(:od_select).with(...)` examples.
  Convert each to the existing `CapturingSelectSet` capture pattern (see lines 60 & 341–349), or
  delete where an existing `CapturingSelectSet` example already covers the same assertion. Preserve
  the behavioural JSON-output coverage the examples provided (individual + collection paths, both
  `id,i` → `%i[id i]` and `c` → `%i[c id]`). `CapturingSelectSet` already defines both `collection`
  and `individual`, so it can capture on both paths.

After migration, `bundle exec rake` must be green with the cop active over both spec trees.

**Likely files:** `.rubocop.yml`, `spec/odata_duty/entity_set/search_spec.rb`,
`spec/odata_duty/entity_set/select_spec.rb`. (Cop runs over both `spec/odata_duty/entity_set/**`
and `spec/odata_duty/schema_builder/**`, but only these two files carry offences today.)

**Defining PRD excerpt:** *External API → Configuration* (the YAML block, "Two patterns not three",
"no Exclude"), *Behavior & expected I/O → Migrating the existing suite* (the three numbered items
and the capture-fixture pattern), *Not offences, deliberately* (do not touch the string/regexp
literal cases in `type_and_container_plumbing_spec.rb` / `schema_structure_spec.rb`).

**Depends on:** Task 1 (the cop file must exist to be required).

### - [ ] Task 3 — Documentation

**Task text:** Apply the PRD's *Documentation impact* section:

- **New:** `spec/using_public_api_only.md`, a contributor guide in the style of
  `spec/using_mutant.md`: what the cop enforces, what the allowlist means (and that it is the
  written definition of the gem's contract), how to respond to each of the four messages, and the
  rule that widening the allowlist is a contract change requiring a `doc/using_*.md` update.
- **Move:** `doc/using_coverage.md` → `spec/using_coverage.md` (git-move, content unchanged). Update
  the two references: `CLAUDE.md` (the `bundle exec rake` bullet) and `spec/using_mutant.md:6`.
- **Update `CLAUDE.md`:** the "Tests must use only the gem's public API" bullet gains a pointer to
  the cop and `spec/using_public_api_only.md`; the "Tests are public documentation" bullet's
  "No stubbing (`stub_const`, mocks) of gem internals" is now enforced (say so); the
  `bundle exec rake` bullet's `doc/using_coverage.md` reference becomes `spec/using_coverage.md`.
- **Update `doc/using_search.md`:** a short note pinning `SearchExpression` and `SearchTerm` as
  public API, listing the methods a consumer may rely on (`.terms`, `.or?`, `term.value`,
  `term.not?`).

Do **not** add a `## Features` entry to `CLAUDE.md` (contributor tooling, not a consumer
capability).

**Likely files:** `spec/using_public_api_only.md` (new), `spec/using_coverage.md` (moved from
`doc/`), `doc/using_coverage.md` (removed), `CLAUDE.md`, `spec/using_mutant.md`,
`doc/using_search.md`.

**Defining PRD excerpt:** *Documentation impact* (all four bullets).

**Depends on:** Tasks 1 & 2 (docs describe the shipped cop, its config, and the published API).
