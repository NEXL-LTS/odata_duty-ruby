# Public-API-only specs with `OdataDuty/PublicApiOnly`

The gem's specs are also its public documentation: they must show a consumer using the gem the
way a consumer would, through its documented surface only. The `OdataDuty/PublicApiOnly` RuboCop
cop enforces that. It reaches into a spec that pokes gem internals and turns "please don't" into
a build failure, so the specs stay honest examples rather than white-box tests.

## What it enforces

The cop runs four checks against every spec:

1. **Internal constants.** A reference to a constant under `OdataDuty::` that is not on the
   allowlist (e.g. `OdataDuty::Executor`) is flagged. Only the outermost constant reports, so
   `OdataDuty::Schema::Metadata` is one offence, not two.
2. **`__`-prefixed methods.** Any call to a method whose name starts with `__` (e.g.
   `__metadata`) is flagged, regardless of receiver — the `__` prefix marks a method internal.
3. **Visibility bypasses.** `send`, `__send__`, `instance_variable_get`, `instance_variable_set`,
   `instance_eval`, `const_get`, and `method` all defeat visibility and are flagged. `public_send`
   is allowed.
4. **Mocking gem behaviour.** `expect_any_instance_of`, `allow_any_instance_of`, and `stub_const`
   fake the gem's own behaviour rather than exercising it, and are flagged.

## What the allowlist means

`.rubocop.yml`'s `OdataDuty/PublicApiOnly` `AllowedConstants` and `AllowedConstantPatterns` **are**
the written definition of the gem's public contract. Everything on it is something a consumer is
meant to touch:

- **Base classes** a consumer subclasses: `EntityType`, `ComplexType`, `EnumType`, `EntitySet`,
  `SetResolver`, `Schema`.
- **Entry points** a consumer calls: `SchemaBuilder`, `EdmxSchema`, `OAS2`.
- **Objects handed to consumer hooks**: `SearchExpression`, `SearchTerm` (see
  `doc/using_search.md`).
- **Rails generators**: `Generators::InstallGenerator`, `Generators::EntitySetGenerator`.
- **Errors**, matched by pattern, so a new error class in `errors.rb` is public automatically.

Nested constants are **not** inherited. `Schema` being public does not make `Schema::Metadata`
public — a nested constant must be listed by its full path to be allowed. The `__` prefix, in turn,
is how a method on a public class declares itself internal.

## Responding to an offence

Each message names the fix:

- **Internal constant** → reach the same behaviour through the documented DSL or entry point
  instead of naming the internal class.
- **`__` method** → call the public equivalent; there is one for anything a consumer needs.
- **Visibility bypass** → assert on observable output — the rendered `$metadata`, `$oas2`, OData
  JSON, or MCP response — rather than poking at internals.
- **Mock** → replace it with a capture fixture on a real `od_*` hook. Define a real, named
  set/resolver that records what the framework handed it, then assert on that record through the
  documented surface. `CapturingSelectSet` (in `spec/odata_duty/entity_set/select_spec.rb`) and
  `CapturingSearchSet` (in `spec/odata_duty/entity_set/search_spec.rb`) are the pattern: each is a
  normal `EntitySet` whose `od_*` hook stashes the value it received, and the examples drive it
  through `Schema.execute` and assert on the captured value.

## Widening the allowlist is a contract change

Adding a constant or pattern to `AllowedConstants` / `AllowedConstantPatterns` promotes something
to public API. Treat it as any other change to the gem's public contract: it is reviewed as such,
and it requires the corresponding `doc/using_*.md` guide to be added or updated so the new surface
is actually documented — publishing `SearchExpression`/`SearchTerm` came with a note in
`doc/using_search.md`, and the next addition should come with the same.

## Notes

- It runs as part of `bundle exec rake` (RuboCop over the repo) — there is no separate command.
- It only lints `spec/**/*_spec.rb`; it does not analyse `lib/`.
- String and regexp literals are not scanned, so asserting on an error message or an `inspect`
  string that happens to mention an internal constant is fine.
