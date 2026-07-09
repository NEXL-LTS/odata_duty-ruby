# Retire the `$search` parser mutation-testing debt

## Summary

Remove all 7 `OdataDuty::SearchExpression*` / `OdataDuty::SearchTerm*` entries from
`.mutant.yml`'s ignore list by pinning the `$search` parsing contract — the parsed expression a
resolver's `od_search` receives, and the errors malformed input raises — as spec-asserted public
behavior in **both** DSL spec trees. No output changes — this is a pure pin. The externally
visible changes are specs, plus accept-mutation simplifications inside the parser where the
surviving mutant is the simpler, behavior-identical code.

```yaml
- "OdataDuty::SearchExpression#and?"
- "OdataDuty::SearchExpression#initialize"
- "OdataDuty::SearchExpression.build_parse_tree"
- "OdataDuty::SearchExpression.parse"
- "OdataDuty::SearchExpression.validate_parse_tree"
- "OdataDuty::SearchTerm#initialize"
- "OdataDuty::SearchTerm#to_s"
```

## Goal / Problem

Measured 2026-07-09 (entries temporarily removed, run scoped to `OdataDuty::SearchExpression*`
and `OdataDuty::SearchTerm*`): **10 subjects, 326 mutations, 279 killed, 47 alive — 85.58%
coverage.** All 47 survivors sit in the 7 ignored subjects; the other three search subjects
(`SearchExpression#or?`, `SearchExpression.transform`, `SearchTerm#not?`) are already clean.

Unlike the `$oas2` retirement, **test selection is not the problem**: mutant found no example
group anchored to these constants and fell back to running all 853 tests against every
mutation, so every existing assertion already counts. The survivors are genuine gaps of two
kinds:

1. **Unasserted public behavior** — the `$search` error contract (which malformed inputs raise
   `NoImplementationError` vs `InvalidQueryOptionError`, and with what message), the empty/
   whitespace-only `$search` behavior, and the operator flags (`and?`) of the expression
   `od_search` receives.
2. **Redundant defensive code** — paths unreachable through the public API (a `nil` guard the
   framework's own guard makes dead, an `Array()` wrap no caller needs, a keyword default no
   caller relies on), where the surviving mutant *is* the correct simplification.

## What it enables

- As a gem consumer implementing `od_search`, the exact shape of the `SearchExpression` I
  receive — `terms`, `and?`/`or?`, each term's `value`/`not?`/`to_s` — is spec-asserted
  contract that cannot silently change.
- As a gem consumer, the error class and message my clients see for unsupported or invalid
  `$search` input (parentheses, mixed AND/OR, illegal characters) is pinned, so my error
  handling and API docs stay truthful.
- As a maintainer, the whole `$search` parsing surface is mutation-gated; regressions fail CI.

## External API

**No new DSL surface.** The pinned surface is the existing `$search` query option
(OData v4.01 `$search`, advertised via `Capabilities.SearchRestrictions` in `$metadata` — see
`doc/using_search.md`) and the `od_search(search_expression)` hook contract, identical in both
DSLs:

```ruby
# Class-based DSL — spec/odata_duty/entity_set/search_spec.rb
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init = @records = PEOPLE
  def collection = @records

  def od_search(search_expression)
    # search_expression.terms   => Array of SearchTerm (value, not?, to_s)
    # search_expression.and?    => true unless the expression used OR
    # search_expression.or?     => true when terms are OR-combined
    @records = @records.select { |r| matches?(r, search_expression) }
  end
end

# Builder DSL — spec/odata_duty/schema_builder/entity_set/search_spec.rb
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init = @records = PEOPLE
  def collection = @records
  def od_search(search_expression) = # same contract as above
end
```

### The pinned contract

- **Empty search** — `$search=` (empty string) and `$search=` of only whitespace call
  `od_search` with an expression whose `terms` is `[]` and whose `and?` is `true` (`or?`
  false). Surrounding whitespace around a non-empty expression is tolerated:
  `$search=  hello  ` behaves exactly like `$search=hello`.
- **Operator flags** — for `$search=a OR b`, `or?` is `true` **and `and?` is `false`**; for
  single terms, implicit AND, and explicit AND, `and?` is `true` and `or?` is `false`. (The
  false side of each flag is currently unasserted — that is what keeps `#and?` alive.)
- **Term shape** — `NOT hello` yields a term with `value == 'hello'` and `not?` true.
  `SearchTerm#to_s` round-trips the OData `searchExpr` syntax: `NOT ` prefix when negated,
  double quotes only when the value contains a space — `NOT "old data"`, `hello`.
- **Error contract** — see Common error cases; classes *and* messages are pinned.

## Behavior & expected I/O

Concrete request → observation pairs the specs must assert, per survivor group:

| Request | Pinned observation | Kills survivors in |
|---|---|---|
| `$search=` and `$search=%20%20` | `od_search` called; `terms == []`, `and?` true, `or?` false | `.parse`, `#initialize` (the `:and` default) |
| `$search=a OR b` | `or?` true and `and?` **false** | `#and?` |
| `$search=(hello` (only `(`) | `NoImplementationError`, message `Parentheses are not supported` | `.build_parse_tree` |
| `$search=hello)` (only `)`) | same | `.build_parse_tree` |
| `$search=hello AND foo!` (unparseable, ` AND ` without ` OR `) | `InvalidQueryOptionError`, message starting `Invalid search expression: ` | `.build_parse_tree` |
| `$search=foo! OR hello` (unparseable, ` OR ` without ` AND `) | same | `.build_parse_tree` |
| `$search=a AND OR AND b` (explicit-AND tree containing the word `OR`) | `NoImplementationError`, message `Mixed AND/OR operators are not supported` | `.validate_parse_tree` |
| `$search=NOT "old data" AND hello` | terms render via `to_s` as `NOT "old data"`, `hello` | `SearchTerm#to_s` (what remains after the accept below) |

The discriminating inputs matter: the existing mixed-operator specs use strings containing
*both* ` AND ` and ` OR `, so mutants that drop either half of the conjunction still pass. An
unparseable input containing only one of the two must raise `InvalidQueryOptionError` (the
fallback), not the mixed-operator `NoImplementationError`.

### Accept-mutation candidates — redundant code, not missing tests

Verified unreachable through the public API (both `schema.execute` and the MCP `search_*` tool
route through the same guard, which returns before parsing when `$search` is absent):

- **`.parse`'s `nil` guard** — no public path passes `nil`; the surviving `nil?`-removal
  mutants are the simplification. Public behavior (empty/whitespace handling above) must be
  pinned *first*, then the guard restructured so the equivalent `strip`/`lstrip`/`rstrip`
  mutants no longer exist (all three are indistinguishable in front of `.empty?`, and the
  parser grammar already tolerates surrounding whitespace).
- **`SearchExpression#initialize`'s `Array(terms)`** — every caller passes an array; with the
  empty-search pin in place, `@terms = terms` is the accepted form.
- **`SearchTerm#initialize`'s `negated: false` default** — every construction site passes
  `negated:` explicitly; making it required (or keeping whichever form mutant accepts) is fine.
- **`SearchTerm#to_s`'s `else ''` branch** — `"#{nil}"` already renders `''`; the accepted form
  is `prefix = ('NOT ' if @negated)`.
- **`.validate_parse_tree`'s `.to_s`** — possibly equivalent (Parslet slice `==` semantics);
  implementer verifies with the `a AND OR AND b` spec in place and accepts if equivalent.

Every accept must leave the request → observation table above green; anything that proves
load-bearing gets a spec instead.

## Common error cases

All existing, now pinned verbatim (classes and messages — see the table above):

- `InvalidQueryOptionError` — `$search` value that fails to parse for any reason other than
  the two named restrictions; message `Invalid search expression: <parser detail>`.
- `NoImplementationError` — parentheses (`Parentheses are not supported`); mixed AND/OR in one
  expression (`Mixed AND/OR operators are not supported`); and, unchanged from today,
  `$search` against a set whose resolver lacks `od_search` (`$search not implemented for …` —
  an `Executor` subject, outside this PRD's entries).

No new errors are introduced.

## Scope

- **In**: deleting the 7 ignore entries; new public-API specs in **both** search spec trees
  (`spec/odata_duty/entity_set/search_spec.rb` and
  `spec/odata_duty/schema_builder/entity_set/search_spec.rb`); accept-mutation simplifications
  in the parser; a gemspec patch bump alongside the `lib/` changes.
- **Out**: any grammar change (parentheses support, mixing AND/OR, new operators), changing
  error classes or messages, the `Executor`/`McpServerBuilder` search entries already retired
  or listed elsewhere, and the other 100+ ignore entries.
- **Verification**: `bundle exec mutant run 'OdataDuty::SearchExpression*'
  'OdataDuty::SearchTerm*'` shows zero alive; `bundle exec rake` stays green. CI's
  `mutant run --since main` will gate the touched subjects automatically once the entries are
  gone.

## Documentation impact

Extends `doc/using_search.md` only if a pin exposes drift — one is already known: the guide's
intro says a missing `od_search` raises `InvalidQueryOptionError`, while its own error-cases
section and the code say `NoImplementationError`. Fix that line while in there. No new guide.

## Open questions

None blocking. The only judgment call is per-survivor accept-vs-spec, and `spec/using_mutant.md`
already defines the rule: accept when the mutant is simpler and behavior-identical through the
public API, spec otherwise.