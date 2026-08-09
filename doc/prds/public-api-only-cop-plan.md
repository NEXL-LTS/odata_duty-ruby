# Build plan — Enforce public-API-only specs with a custom RuboCop cop

PRD: [public-api-only-cop.md](./public-api-only-cop.md)

## Notes on scope

This PRD is **developer tooling** — a custom RuboCop cop that lints `spec/**/*_spec.rb`.
It introduces **no DSL surface** and changes **no** `$metadata`/`$oas2`/OData JSON/MCP
output. The "two parallel DSLs — keep both in sync" rule therefore does **not** apply here:
there is nothing to implement in either DSL. The one contract change is *publishing*
`OdataDuty::SearchExpression` / `OdataDuty::SearchTerm` (already documented in
`doc/using_search.md`), which is realised purely by adding them to the cop's allowlist —
no code change to those classes.

The cop lives at `rubocop/cop/odata_duty/public_api_only.rb` under
`RuboCop::Cop::OdataDuty::PublicApiOnly`. It is held to the repo's 100% line+branch
SimpleCov bar (no `add_filter` for `rubocop/`) and RuboCop's own tightened metrics.

## Tasks

### Task 1 — The cop, its config, and its spec at 100% coverage

- [x] **Task text:** Create the custom RuboCop cop `OdataDuty/PublicApiOnly` at
  `rubocop/cop/odata_duty/public_api_only.rb` (namespace
  `RuboCop::Cop::OdataDuty::PublicApiOnly`). Wire it into `.rubocop.yml` via a relative
  `require: - ./rubocop/cop/odata_duty/public_api_only.rb` and the full config block
  (Enabled, Namespace, Include `spec/**/*_spec.rb`, AllowedConstants list,
  AllowedConstantPatterns two patterns). Write its spec at
  `spec/rubocop/public_api_only_spec.rb` using RuboCop's own RSpec support
  (`require 'rubocop/rspec/support'`, no new dependency), requiring the cop file so
  SimpleCov tracks it. The cop implements four independent checks, each with its own
  message:
    1. **Internal constant** (`on_const`): a const node whose full path starts with
       `OdataDuty::` and is neither in `AllowedConstants` nor matched by
       `AllowedConstantPatterns`. Report on the **outermost** const only (guard
       `return if node.parent&.const_type?`) so `OdataDuty::Schema::Metadata` reports once.
    2. **Internal method** (`on_send`/`on_csend`): a send whose method name starts with
       `__`. Receiver-agnostic.
    3. **Visibility bypass** (`on_send`): method name is one of `send`, `__send__`,
       `instance_variable_get`, `instance_variable_set`, `instance_eval`, `const_get`,
       `method`. `public_send` is NOT a bypass. `__send__` must report **once** (bypass,
       not also as `__`-prefixed).
    4. **Mocking gem behaviour** (`on_send`): method name is one of
       `expect_any_instance_of`, `allow_any_instance_of`, `stub_const`.
  Namespace read via `cop_config.fetch('Namespace', 'OdataDuty')`; allowed constants
  memoised via `@allowed_constants ||= Set.new(...)` (both coverage-safe — `fetch` and
  `||=` emit no branch). No defensive/unreachable branches; no inline RuboCop disables;
  MethodLength 13, AbcSize 30, CyclomaticComplexity 7, 99-char lines.
- **Definition of done (PRD excerpt):** the *Configuration*, *What the cop checks*,
  *Behavior & expected I/O* (Offences + Accepted), *Common error cases* (four messages),
  *Coverage and mutation testing*, and *Cop spec* sections. Messages verbatim:
    - Constant: `` `<const>` is not part of the public API. Specs must exercise the gem
      through its documented surface. ``
    - Internal method: `` `<name>` is an internal method (`__` prefix). Specs must
      exercise the gem through its documented surface. ``
    - Bypass: `` `<name>` bypasses method visibility. Specs must exercise the gem through
      its documented surface. ``
    - Mock: `` `<name>` mocks gem behaviour. Specs must assert on the gem's output
      instead. ``
  Cop spec must cover, at minimum: allowlisted constant accepted; a constant matched by
  **each** error pattern accepted; internal constant flagged; nested constant under an
  allowlisted parent flagged **once** not twice; `__`-prefixed call flagged regardless of
  receiver; **each** bypass method flagged; `public_send` accepted; **each** mocking
  method flagged; `__send__` flagged once; a cop_config with no `Namespace` key exercising
  the default. Four branch arms for the outermost-const guard (top-level const with nil
  parent; const whose parent is not a const; nested const guard taken; allowed const
  falling through).
- **Likely files:** `rubocop/cop/odata_duty/public_api_only.rb` (new),
  `.rubocop.yml` (require + config block), `spec/rubocop/public_api_only_spec.rb` (new).
  No `lib/` change. No DSL/spec-tree change (developer tooling only).
- **Depends on:** nothing.

### Task 2 — Migrate the five existing offences in the suite

- [ ] **Task text:** With the cop enabled (Task 1), `bundle exec rake` now flags five
  offences. Resolve all so RuboCop is green:
    - `spec/odata_duty/entity_set/search_spec.rb:157` — the single constant offence AND a
      mock: `expect_any_instance_of(SupportsCollectionSearchSet).to
      receive(:od_search).with(instance_of(OdataDuty::SearchExpression)).and_call_original`.
      `OdataDuty::SearchExpression` is now allowlisted (Task 1) so the constant is fine,
      but the **mock must go**. Replace with a capturing-set fixture that records the
      `SearchExpression` its `od_search` received, then assert on the documented surface
      (`expression.terms`, `expression.or?`) — not on the object's class. Model it on the
      existing `CapturingSelectSet` pattern in `select_spec.rb`.
    - `spec/odata_duty/entity_set/select_spec.rb` lines 151, 167, 241, 259 — four
      `expect_any_instance_of(SupportsCollectionSelectSet).to
      receive(:od_select).with(...).and_call_original` mocks. Each is converted to the
      capture-fixture pattern (`CapturingSelectSet` already exists at line 60 and lines
      341–349 already assert on `captured_select`), or **deleted where the existing
      `CapturingSelectSet` examples already cover the same assertion**. The four examples
      also assert on the real `$select` JSON output; that JSON assertion is legitimate and
      should be preserved (drop only the mock line) unless the identical
      output+hook-arg pairing is already covered.
  Do not weaken any assertion on observable output. Confirm the two deliberate
  non-offences (regexp/string literal constant refs in
  `type_and_container_plumbing_spec.rb:124` and `schema_structure_spec.rb:132`) remain
  unflagged.
- **Definition of done (PRD excerpt):** *Migrating the existing suite* (items 1, 2, 3),
  *Not offences, deliberately*. Result: `bundle exec rake` green; no
  `expect_any_instance_of`/`allow_any_instance_of`/`stub_const` remain in any
  `*_spec.rb`; the capture fixtures assert on `od_select` args / `od_search` terms via the
  documented surface.
- **Likely files:** `spec/odata_duty/entity_set/search_spec.rb`,
  `spec/odata_duty/entity_set/select_spec.rb`.
- **Depends on:** Task 1 (cop must exist and be enabled to produce the offences).

### Task 3 — Documentation impact

- [ ] **Task text:** Apply the PRD's *Documentation impact* section:
    - **New** `spec/using_public_api_only.md` — contributor guide in the style of
      `spec/using_mutant.md`: what the cop enforces, what the allowlist means, how to
      respond to each of the four messages, and the rule that widening the allowlist is a
      contract change requiring a `doc/using_*.md` update.
    - **Move** `doc/using_coverage.md` → `spec/using_coverage.md` (git mv). Update the two
      references: `CLAUDE.md` (the `bundle exec rake` command bullet) and
      `spec/using_mutant.md:6`.
    - **Update `CLAUDE.md`:** the "Tests must use only the gem's public API" convention
      bullet gains a pointer to the cop and `spec/using_public_api_only.md`; the "Tests are
      public documentation" bullet's "No stubbing (`stub_const`, mocks)" becomes stated as
      enforced; the `bundle exec rake` bullet's `doc/using_coverage.md` becomes
      `spec/using_coverage.md`. Also add a one-line entry to the `## Features`/tooling area
      if warranted (this is contributor tooling, so a pointer in the conventions bullet is
      the right home — no consumer `## Features` entry, since nothing consumer-visible
      changed except the already-documented `SearchExpression` publication).
    - **Update `doc/using_search.md`** — a short note pinning `SearchExpression` and
      `SearchTerm` as public API, listing the methods a consumer may rely on (`.terms`,
      `.or?`, `term.value`, `term.not?`).
- **Definition of done (PRD excerpt):** the entire *Documentation impact* section.
- **Likely files:** `spec/using_public_api_only.md` (new), `doc/using_coverage.md` →
  `spec/using_coverage.md` (moved), `CLAUDE.md`, `spec/using_mutant.md`,
  `doc/using_search.md`.
- **Depends on:** Task 1 (guide describes the enabled cop), Task 2 (suite is green).
