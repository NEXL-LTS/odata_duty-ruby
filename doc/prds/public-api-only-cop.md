# Enforce public-API-only specs with a custom RuboCop cop

## Summary

A custom RuboCop cop, `OdataDuty/PublicApiOnly`, that fails the build when a spec
reaches past the gem's documented public API — by naming an internal constant,
calling a `__`-prefixed internal method, bypassing method visibility, or mocking
gem behaviour. The allowlist of public constants lives in `.rubocop.yml`, so it
doubles as the written definition of the gem's contract.

This is developer tooling for contributors, not a consumer-facing capability. It
introduces no new DSL surface and no change to `$metadata`, `$oas2`, the OData
JSON, or the MCP tools. The one consumer-visible change it forces is a decision
that was already implicit: `OdataDuty::SearchExpression` and its terms are
formally part of the public API.

## Goal / Problem

`CLAUDE.md` already carries the rule:

> **Tests must use only the gem's public API.** … Never test internal
> classes/methods directly.

Today nothing enforces it. The last change shipped several specs that drove
internals directly, and they were only caught by review. Prose conventions erode;
a cop does not.

Three concrete costs of letting it erode:

- **Refactors get expensive.** A spec coupled to `Executor` or `MapperBuilder`
  breaks when internals move, even though no consumer-visible behaviour changed.
- **Coverage stops meaning what it claims.** A spec that drives an internal class
  proves the class works in isolation, not that any consumer can reach the
  behaviour. Public-API-only specs collapse those two questions into one.
- **The specs stop being documentation.** `CLAUDE.md` states "tests are public
  documentation". That only holds if the public DSL is the only way to set a
  scenario up.

**Current state.** Measured against `main` across 174 spec files, the discipline
mostly holds — this is a ratchet, not a migration:

| Check | Count |
|---|---|
| Internal constants referenced in `spec/**/*_spec.rb` | 1 |
| `send` / `__send__` / `instance_variable_get` / `const_get` / `instance_eval` | 0 |
| `__`-prefixed internal method calls | 0 |
| `stub_const` | 0 |
| `expect_any_instance_of` / `allow_any_instance_of` | 5 (in 2 files) |

Note the audit differs from the original proposal, which counted three constant
offences by grep. Two of those three are inside a **regexp literal** and a
**string literal** — `on_const` never sees them, so the cop does not flag them.
That is the intended outcome; see *Scope*.

## What it enables

- As a contributor, when I write a spec that reaches into gem internals, `bundle
  exec rake` fails locally and in CI with a message naming the constant or method
  and telling me to go through the documented surface.
- As a contributor, I can read `.rubocop.yml` to see exactly which constants are
  public, without inferring it from `lib/`.
- As a maintainer, widening the public API becomes a visible diff to the
  allowlist that goes through review, rather than a spec quietly reaching around
  the contract.
- As a maintainer, a surviving mutant in an internal class becomes a real
  question — "is this branch reachable from the documented surface at all?" —
  rather than a prompt to write a unit test for the internal.

Out of bounds: the cop does not analyse `lib/`, does not restrict what internals
may exist, and does not attempt type inference (see *Scope*).

## External API

### The public-API allowlist

This is the contract, expressed as configuration. It falls into four groups taken
from the README.

**Base classes a consumer subclasses**

`EntityType`, `ComplexType`, `EnumType`, `EntitySet`, `SetResolver`, `Schema`

**Entry points a consumer calls**

`SchemaBuilder`, `EdmxSchema`, `OAS2`

**Objects the framework hands to consumer hooks**

`SearchExpression`, `SearchTerm` — `doc/using_search.md` documents `od_search`
as receiving a `SearchExpression` and documents `.terms`, `.or?`, `term.value`
and `term.not?` as things a consumer calls. Publishing them makes the allowlist
match the guide that already exists.

These are coined names, not OData terms: the OData v4 `$search` grammar defines
the *syntax* of a search expression but names no object type for the parsed
result, so there is no vocabulary term to track.

**Rails generators**

`Generators::InstallGenerator`, `Generators::EntitySetGenerator` — consumer-facing,
invoked as `bin/rails generate odata_duty:install`.

**Errors**

Everything in `errors.rb`, because consumers rescue them. Allowed by pattern
rather than by name, so new error classes are public automatically — the correct
default.

Everything else in `lib/` is internal: `Executor`, `MapperBuilder`,
`ContextWrapper`, `CreateComplexTypeHashWrapper`, `Filter`, `FilterPredicate`,
`ParsletSearchExpression*`, `McpServerBuilder`, `McpIdentifierValidator`,
`McpInputSchemas`, `Property`, `EnumMember`, the `Edm*` types, and the OAS2 path
classes.

Two rules follow:

1. **Nested constants are not inherited.** `Schema` being public does not make
   `Schema::Metadata` or `SchemaBuilder::Schema` public. This is the case that
   leaks in practice, so a nested constant is allowed only when its full path is
   listed.
2. **`__` prefix means internal.** The gem already uses this (`__metadata`,
   `__load`, `__to_value`, `__wrap`, `__member_names`). Formalising it gives the
   cop a receiver-agnostic signal, which matters because RuboCop cannot infer
   types. Every new internal method on a public class should carry the prefix.

Changing the allowlist is a change to the gem's contract, reviewed like any other
public API change, with the `doc/using_*.md` update that implies.

### Configuration

Merged into `.rubocop.yml`:

```yaml
require:
  - ./rubocop/cop/odata_duty/public_api_only.rb

OdataDuty/PublicApiOnly:
  Enabled: true
  Namespace: OdataDuty
  Include:
    - 'spec/**/*_spec.rb'
  AllowedConstants:
    # Base classes a consumer subclasses
    - OdataDuty::EntityType
    - OdataDuty::ComplexType
    - OdataDuty::EnumType
    - OdataDuty::EntitySet
    - OdataDuty::SetResolver
    - OdataDuty::Schema
    # Entry points a consumer calls
    - OdataDuty::SchemaBuilder
    - OdataDuty::EdmxSchema
    - OdataDuty::OAS2
    # Handed to od_search; see doc/using_search.md
    - OdataDuty::SearchExpression
    - OdataDuty::SearchTerm
    # Rails generators, invoked as `bin/rails generate odata_duty:install`
    - OdataDuty::Generators::InstallGenerator
    - OdataDuty::Generators::EntitySetGenerator
  AllowedConstantPatterns:
    # Errors are part of the contract: consumers rescue them. Deriving these by
    # pattern means new error classes in errors.rb are public automatically.
    - '\AOdataDuty::\w*Error\z'
    - '\AOdataDuty::Invalid\w+\z'
```

Two patterns, not three. Every class in `errors.rb` matches one of them: those
ending in `Error`, and the four that do not (`InvalidValue`, `InvalidType`,
`InvalidFilterValue`, `InvalidPropertyReferenceValue`). The proposal's third
pattern was fully redundant with the first.

There is no `Exclude`. Every `*_spec.rb` under `spec/` is covered.

`bundle exec rake` already runs RuboCop over the whole repo, so no CI workflow
change is needed. The gemspec ships `Dir['CHANGELOG.md', 'lib/**/*', 'LICENSE',
'README.md']`, so a top-level `rubocop/` directory ships nothing to consumers and
no gemspec change is needed either.

### What the cop checks

Four independent checks, each with its own message:

| Check | Trigger | Applies to |
|---|---|---|
| Internal constant | A constant node whose full path starts with `OdataDuty::` and is neither in `AllowedConstants` nor matched by `AllowedConstantPatterns` | Outermost const only, so `OdataDuty::Schema::Metadata` reports once |
| Internal method | A send/csend whose method name starts with `__` | Receiver-agnostic |
| Visibility bypass | `send`, `__send__`, `instance_variable_get`, `instance_variable_set`, `instance_eval`, `const_get`, `method` | Any receiver |
| Mocking gem behaviour | `expect_any_instance_of`, `allow_any_instance_of`, `stub_const` | Any receiver |

`public_send` is deliberately **not** a bypass — resolver fixtures legitimately
dispatch on property names with it, and all 26 existing `send(` grep matches in
the suite are `public_send`.

`const_get` being flagged is what closes the obvious hole:
`Object.const_get('OdataDuty::Executor')` sidesteps the constant check at the AST
level but is caught as a bypass.

## Behavior & expected I/O

### Offences

```ruby
# spec/odata_duty/entity_set/some_spec.rb

OdataDuty::Executor.execute(url: url, schema: schema)
^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must
                    exercise the gem through its documented surface.

OdataDuty::Schema::Metadata.new(schema)
^^^^^^^^^^^^^^^^^^^^^^^^^^^ `OdataDuty::Schema::Metadata` is not part of the public
                            API. Specs must exercise the gem through its documented surface.

schema.__metadata.entity_sets
       ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must
                  exercise the gem through its documented surface.

set.send(:converted_id, '1')
    ^^^^ `send` bypasses method visibility. Specs must exercise the gem through
         its documented surface.

expect_any_instance_of(PeopleSet).to receive(:od_select)
^^^^^^^^^^^^^^^^^^^^^^ `expect_any_instance_of` mocks gem behaviour. Specs must
                       assert on the gem's output instead.
```

### Accepted

```ruby
class PeopleSet < OdataDuty::EntitySet; end          # allowlisted base class
OdataDuty::EdmxSchema.metadata_xml(SampleSchema)     # allowlisted entry point
expect { subject }.to raise_error(OdataDuty::ResourceNotFoundError)  # error pattern
expect { subject }.to raise_error(OdataDuty::InvalidType)            # error pattern
def od_search(expression) = expression.terms         # SearchExpression allowlisted
record.public_send(property_name)                    # not a bypass
```

### Migrating the existing suite

Turning the cop on produces offences in three places. All three must be resolved
in the same change so `bundle exec rake` is green.

**1. `spec/odata_duty/entity_set/search_spec.rb:157`** — the single constant
offence:

```ruby
expect_any_instance_of(SupportsCollectionSearchSet)
  .to receive(:od_search).with(instance_of(OdataDuty::SearchExpression)).and_call_original
```

This is both a constant reference and a mock. `OdataDuty::SearchExpression` moves
to the allowlist (it is documented API), but the mock still has to go — see below.

**2. Four `expect_any_instance_of` uses in
`spec/odata_duty/entity_set/select_spec.rb`** (lines 151, 167, 241, 259), each of
the form:

```ruby
expect_any_instance_of(SupportsCollectionSelectSet)
  .to receive(:od_select).with(%i[id i]).and_call_original
```

The replacement pattern **already exists in the same file**: `CapturingSelectSet`
(line 60) records what the framework passed it, and lines 342–349 assert on that
recording:

```ruby
class CapturingSelectSet < OdataDuty::EntitySet
  class << self
    attr_accessor :captured_select
  end

  def od_select(select)
    self.class.captured_select = select
    # …
  end
end

it 'hands od_select the resolved property names' do
  schema.execute('CapturingSelect', context: Context.new,
                                    query_options: { '$select' => 'id,i' })
  expect(CapturingSelectSet.captured_select).to eq(%i[id i])
end
```

Each of the four mocked examples is either converted to this capture-fixture
pattern or deleted where the existing `CapturingSelectSet` examples already cover
the same assertion. The search-spec case (1) gets an equivalent capturing set
that records the `SearchExpression` it received; the example then asserts on
`expression.terms` and `expression.or?` — the documented surface — rather than on
the object's class.

This is strictly better documentation: the fixture shows a consumer what their
`od_select` / `od_search` implementation actually receives, instead of a mock
asserting it from outside.

**3. Nothing else.** No `send`, `__send__`, `instance_variable_get`,
`const_get`, `instance_eval`, `stub_const`, or `__`-prefixed call exists in any
`*_spec.rb` today.

### Not offences, deliberately

Two grep hits look like leaks but are assertions on **observable output**, and
`on_const` does not see them because they are string and regexp literals:

```ruby
# spec/odata_duty/schema_builder/type_and_container_plumbing_spec.rb:124
expect { create('Pending') }.to raise_error(
  OdataDuty::InvalidType, /Pending is not a valid member of \[#<OdataDuty::EnumMember/
)

# spec/odata_duty/schema_builder/schema_structure_spec.rb:132
expect(inspected).to eq('#<OdataDuty::SchemaBuilder::Schema @namespace=SampleSpace …>')
```

An error message and an `inspect` string are things a consumer sees, so asserting
on them is legitimate. Extending the cop to scan literals would flag these as
false positives. Left as-is.

### Coverage and mutation testing

The cop is held to the same bar as `lib/`: SimpleCov's 100% line and branch
enforcement applies, with **no** `add_filter` for `rubocop/`. The cop spec
requires the cop file, so SimpleCov tracks it from the first example.

This constrains the cop's design: it must carry no defensive or unreachable
branches, because every branch needs an example that exercises it. Notably, the
`Namespace` config default needs an example with no `Namespace` key set, and the
outermost-const guard needs both a nested and a non-nested case.

Mutant is unaffected — `.mutant.yml` sets `includes: lib` and matches subjects
under `OdataDuty*`, while the cop lives in `rubocop/` under
`RuboCop::Cop::OdataDuty::PublicApiOnly`.

The cop file itself is linted by RuboCop (nothing in `AllCops.Exclude` covers
`rubocop/`), so it must satisfy the repo's tightened metrics: `MethodLength` 13,
`AbcSize` 30, 99-char lines, no inline disables.

### Cop spec

`spec/rubocop/public_api_only_spec.rb`, using RuboCop's own RSpec support
(`rubocop/rspec/support`, shipped with the `rubocop` gem — no new dependency).
It must cover, at minimum:

- an allowlisted constant, accepted
- a constant matched by each error pattern, accepted
- an internal constant, flagged
- a nested constant under an allowlisted parent, flagged once, not twice
- a `__`-prefixed method call, flagged regardless of receiver
- each bypass method, flagged
- `public_send`, accepted
- each mocking method, flagged
- a cop_config with no `Namespace` key, exercising the default

Heredocs in this file contain internal constant names as *strings*, so the cop
does not flag its own spec.

## Common error cases

The cop reports offences; it never raises. Four messages, one per check:

| Situation | Message |
|---|---|
| Constant outside the allowlist | `` `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface. `` |
| `__`-prefixed method call | `` `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface. `` |
| Visibility bypass | `` `send` bypasses method visibility. Specs must exercise the gem through its documented surface. `` |
| Mocking gem behaviour | `` `expect_any_instance_of` mocks gem behaviour. Specs must assert on the gem's output instead. `` |

Failure modes to guard against, each of which must be covered by the cop spec:

- **Missing cop file.** A wrong path in `.rubocop.yml`'s `require:` makes RuboCop
  fail to load with `cannot load such file`. The relative `./rubocop/…` form is
  required so it resolves from the repo root.
- **Double-reporting nested constants.** Without the outermost-const guard,
  `OdataDuty::Schema::Metadata` reports twice — once for `OdataDuty::Schema` and
  once for the full path.
- **Flagging `public_send`.** Naive prefix matching on `send` would break 26
  legitimate fixture call sites.
- **Flagging `__send__` twice.** It is both a bypass method and `__`-prefixed;
  it must report once.

## Scope

**In**

- A new cop at `rubocop/cop/odata_duty/public_api_only.rb`.
- Its spec at `spec/rubocop/public_api_only_spec.rb`, at 100% line and branch
  coverage.
- `.rubocop.yml` config: `require`, allowlist, patterns, `Include`.
- Migrating the five existing offences (one constant, five mocks — one overlaps).
- Contributor documentation (see below).

**Out**

- `lib/` is not analysed. The cop only runs on `spec/**/*_spec.rb`.
- `spec/config.ru`, `spec/spec_helper.rb` and other non-`_spec.rb` files are not
  covered. `config.ru`'s `record.send(property_name)` is a consumer calling a
  method on their own object, not a bypass of gem visibility, and `config.ru` is
  the canonical integration example rather than a test.
- String and regexp literals are not scanned (see *Not offences, deliberately*).
- No type inference. `subject.some_internal` where `subject` holds an `Executor`
  is invisible to the cop. Two things keep that hole small: getting hold of an
  internal object requires naming an internal constant, which is flagged; and the
  `__` prefix is receiver-agnostic, so any internal method carrying it is caught
  wherever it is called. Applying the prefix consistently to new internal methods
  on public classes is what makes the rule hold in practice.
- No consumer-facing behaviour changes. No DSL, `$metadata`, `$oas2`, OData JSON
  or MCP output is affected. The only contract change is publishing
  `SearchExpression` / `SearchTerm`, which `doc/using_search.md` already
  documented.
- Both DSLs are covered equally, since the cop runs on both spec trees
  (`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`), but
  neither DSL changes.

## Documentation impact

**New: `spec/using_public_api_only.md`** — a contributor guide in the style of
`spec/using_mutant.md`: what the cop enforces, what the allowlist means, how to
respond to each of the four messages, and the rule that widening the allowlist is
a contract change requiring a `doc/using_*.md` update.

**Move: `doc/using_coverage.md` → `spec/using_coverage.md`** — so all three
test-suite discipline docs (mutant, coverage, public-API) sit together in
`spec/`, next to the suite they govern, rather than mixed in with the
consumer-facing `doc/using_*.md` guides. Update the two references:
`CLAUDE.md:29` and `spec/using_mutant.md:6`.

**Update `CLAUDE.md`:**
- The "Tests must use only the gem's public API" convention bullet gains a
  pointer to the cop and to `spec/using_public_api_only.md`.
- The "Tests are public documentation" bullet's "No stubbing (`stub_const`,
  mocks) of gem internals" becomes enforced rather than advisory, and should say
  so.
- The `bundle exec rake` command bullet's `doc/using_coverage.md` reference
  becomes `spec/using_coverage.md`.

**Update `doc/using_search.md`** — a short note pinning `SearchExpression` and
`SearchTerm` as public API, listing the methods a consumer may rely on
(`.terms`, `.or?`, `term.value`, `term.not?`), since the allowlist now makes that
a formal commitment.
