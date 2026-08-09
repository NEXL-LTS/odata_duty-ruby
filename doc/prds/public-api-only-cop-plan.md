# Build Plan for public-api-only-cop

> Implements [public-api-only-cop.md](./public-api-only-cop.md)

## Task 1: Create the RuboCop cop and its spec
**Status:** - [x]

**Task text:** Write the custom RuboCop cop `rubocop/cop/odata_duty/public_api_only.rb` that checks for four violations: internal constants not in the allowlist, `__`-prefixed method calls, visibility bypasses (send, __send__, instance_variable_get/set, const_get, instance_eval, method), and mocking methods (expect_any_instance_of, allow_any_instance_of, stub_const). Write its spec at `spec/rubocop/public_api_only_spec.rb` at 100% line and branch coverage.

**Likely files:** 
- `rubocop/cop/odata_duty/public_api_only.rb` (new)
- `spec/rubocop/public_api_only_spec.rb` (new)

**Defining PRD excerpt:** The cop must check:
- Internal constant: a constant path starting with `OdataDuty::` not in `AllowedConstants` or matched by `AllowedConstantPatterns`, reporting once (outermost only)
- Internal method: method name starting with `__`, receiver-agnostic
- Visibility bypass: send, __send__, instance_variable_get, instance_variable_set, instance_eval, const_get, method calls
- Mocking: expect_any_instance_of, allow_any_instance_of, stub_const
- public_send must NOT be flagged
- __send__ must report once (not twice)
- Must satisfy 100% line + branch coverage, 99-char lines, MethodLength 13, AbcSize 30

**Dependencies:** None (foundation task)

## Task 2: Configure the cop in .rubocop.yml
**Status:** - [x]

**Task text:** Add the cop configuration to `.rubocop.yml` with the require directive, the allowlist of public constants (EntityType, ComplexType, EnumType, EntitySet, SetResolver, Schema, SchemaBuilder, EdmxSchema, OAS2, SearchExpression, SearchTerm, Generators::InstallGenerator, Generators::EntitySetGenerator), and two AllowedConstantPatterns for errors and invalid types.

**Likely files:**
- `.rubocop.yml` (update)

**Defining PRD excerpt:** Configuration must be:
```yaml
require:
  - ./rubocop/cop/odata_duty/public_api_only.rb

OdataDuty/PublicApiOnly:
  Enabled: true
  Namespace: OdataDuty
  Include:
    - 'spec/**/*_spec.rb'
  AllowedConstants:
    - OdataDuty::EntityType
    - OdataDuty::ComplexType
    - OdataDuty::EnumType
    - OdataDuty::EntitySet
    - OdataDuty::SetResolver
    - OdataDuty::Schema
    - OdataDuty::SchemaBuilder
    - OdataDuty::EdmxSchema
    - OdataDuty::OAS2
    - OdataDuty::SearchExpression
    - OdataDuty::SearchTerm
    - OdataDuty::Generators::InstallGenerator
    - OdataDuty::Generators::EntitySetGenerator
  AllowedConstantPatterns:
    - '\AOdataDuty::\w*Error\z'
    - '\AOdataDuty::Invalid\w+\z'
```

**Dependencies:** Task 1 (cop must exist)

## Task 3: Migrate spec violations - search_spec.rb and select_spec.rb (MERGED INTO TASK 2)
**Status:** - [x]

**Task text:** Fix the five offences currently in the spec suite: one constant reference to SearchExpression in search_spec.rb:157, and four expect_any_instance_of calls in select_spec.rb (lines 151, 167, 241, 259). Create a CapturingSearchSet fixture in search_spec.rb that records the SearchExpression passed to od_search, then assert on expression.terms and expression.or?. Convert the four select_spec.rb mocks to use or extend CapturingSelectSet pattern, or delete where existing capturing examples already cover the assertion.

**Likely files:**
- `spec/odata_duty/entity_set/search_spec.rb` (update)
- `spec/odata_duty/entity_set/select_spec.rb` (update)

**Defining PRD excerpt:** The changes must:
- Allow SearchExpression as a public constant (it is documented API in doc/using_search.md)
- Remove the mock in search_spec.rb:157 by creating CapturingSearchSet that records the SearchExpression passed to od_search, asserting on documented surface (.terms, .or?)
- Convert or delete four mocks in select_spec.rb using the CapturingSelectSet pattern already present in the file, or by verifying existing examples already cover the assertion
- Result: no offences when the cop runs

**Dependencies:** Tasks 1-2 (cop and config in place)

## Task 4: Create contributor documentation
**Status:** - [ ]

**Task text:** Write `spec/using_public_api_only.md` as a contributor guide explaining what the cop enforces, the four violation types with their messages, how to respond to each, the allowlist and what it means, and the rule that widening it is a contract change. Also move `doc/using_coverage.md` to `spec/using_coverage.md`.

**Likely files:**
- `spec/using_public_api_only.md` (new)
- `doc/using_coverage.md` → `spec/using_coverage.md` (move)

**Defining PRD excerpt:** The guide must cover:
- What the cop enforces: the four checks
- Each violation message and how to fix it
- The allowlist and why it matters
- That widening the allowlist is a contract change
- In style of `spec/using_mutant.md`

**Dependencies:** Tasks 1-3 (cop, config, migrations complete)

## Task 5: Update CLAUDE.md references
**Status:** - [ ]

**Task text:** Update CLAUDE.md to point the "Tests must use only the gem's public API" bullet to the cop and `spec/using_public_api_only.md`, update the "Tests are public documentation" bullet to note mocking is now enforced, and change the `doc/using_coverage.md` reference to `spec/using_coverage.md`.

**Likely files:**
- `CLAUDE.md` (update)

**Defining PRD excerpt:** Changes to:
- "Tests must use only the gem's public API" bullet: add pointer to cop and spec/using_public_api_only.md
- "Tests are public documentation" bullet: note "No stubbing (`stub_const`, mocks) of gem internals" is now enforced
- "bundle exec rake" command bullet: change doc/using_coverage.md reference to spec/using_coverage.md

**Dependencies:** Task 4 (guide created, coverage.md moved)

## Task 6: Update doc/using_search.md to formalize SearchExpression/SearchTerm as public
**Status:** - [ ]

**Task text:** Add a note to `doc/using_search.md` pinning `SearchExpression` and `SearchTerm` as public API, listing the methods a consumer may rely on: `.terms`, `.or?`, `term.value`, `term.not?`.

**Likely files:**
- `doc/using_search.md` (update)

**Defining PRD excerpt:** The note must state that SearchExpression and SearchTerm are public API and list the documented surface (.terms, .or?, term.value, term.not?).

**Dependencies:** Task 1 (cop and allowlist in place)

## Final Review
**Status:** - [ ]

Check the entire diff against the PRD: cop, config, migrations all complete, specs pass, both DSLs covered (note: this PRD doesn't touch DSLs, only specs and tooling), docs updated, CLAUDE.md current, -plan.md all ticked, rake green.

**Dependencies:** All tasks 1-6
