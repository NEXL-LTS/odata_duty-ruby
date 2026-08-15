# The `OdataDuty/PublicApiOnly` cop

`CLAUDE.md` requires that specs exercise the gem **only through its documented public API** —
the DSL, `Schema.execute`/`.create`/`.update`/`.delete`, the rendered `$metadata`/`$oas2`/index,
`OAS2.build_json`, and `to_mcp_server` with its JSON-RPC calls. A test that reaches past that
surface into an internal class, method, or instance variable stops being usable documentation and
starts coupling the suite to implementation details. `OdataDuty/PublicApiOnly`
(`rubocop/cop/odata_duty/public_api_only.rb`) makes that rule enforceable rather than advisory: it
runs against `spec/**/*_spec.rb` as part of `bundle exec rubocop` (and therefore `bundle exec
rake`).

## What it checks

Four checks, each with its own message:

1. **Internal constant.** A constant reference under the `OdataDuty::` namespace that is not on the
   allowlist. `` `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem
   through its documented surface. ``
2. **`__`-prefixed internal method.** Any method call whose name starts with `__` (e.g.
   `__metadata`, `__send__`). `` `__metadata` is an internal method (`__` prefix). Specs must
   exercise the gem through its documented surface. ``
3. **Visibility bypass.** A call to `send`, `__send__`, `instance_variable_get`,
   `instance_variable_set`, `instance_eval`, `const_get`, or `method`. `` `send` bypasses method
   visibility. Specs must exercise the gem through its documented surface. `` (`public_send` is
   deliberately allowed — it respects visibility, so it only reaches genuinely-public methods.)
4. **Mocking gem behaviour.** A call to `expect_any_instance_of`, `allow_any_instance_of`, or
   `stub_const`. `` `stub_const` mocks gem behaviour. Specs must assert on the gem's output
   instead. ``

## The allowlist is the public contract

`AllowedConstants` and `AllowedConstantPatterns` in the `OdataDuty/PublicApiOnly` block of
`.rubocop.yml` are the *written definition* of the gem's public constant surface. What's listed:

- **Base classes a consumer subclasses:** `EntityType`, `ComplexType`, `EnumType`, `EntitySet`,
  `SetResolver`, `Schema`.
- **Entry points a consumer calls:** `SchemaBuilder`, `EdmxSchema`, `OAS2`.
- **The objects handed to `od_search`:** `SearchExpression`, `SearchTerm` (see
  `../doc/using_search.md`).
- **The Rails generators:** `Generators::InstallGenerator`, `Generators::EntitySetGenerator`.
- **All of `errors.rb`, by pattern:** `AllowedConstantPatterns` matches `OdataDuty::*Error` and
  `OdataDuty::Invalid*`, so new error classes are public automatically — consumers rescue them.

Two rules follow from how the cop reads the list:

- **Nested constants are not inherited.** A constant counts as public only if its *full path* is
  listed. `OdataDuty::EntitySet` being allowed does not make some `OdataDuty::EntitySet::Inner`
  allowed; it would need its own entry.
- **The `__` prefix marks a method internal**, regardless of the allowlist — the allowlist covers
  constants, not methods.

## Responding to an offence

The fix is almost always to go through the documented surface, not to reach around the cop:

- **Internal constant / `__`-prefixed method.** Drive the behaviour through the DSL and
  `Schema.execute` (or the builder equivalent) and assert on the rendered output
  (`$metadata`/`$oas2`/MCP JSON) instead of poking at the internal object. For a `__`-prefixed
  *Ruby builtin* (e.g. `__dir__`), use the non-`__` equivalent — `File.dirname(__FILE__)`.
- **Visibility bypass / mocking.** Instead of stubbing or bypassing to observe what a hook
  receives, use a **capture fixture**: a real entity set that records its argument and exposes it
  as public state, then assert on that. Worked examples in the suite:
  - `CapturingSelectSet` in `odata_duty/entity_set/select_spec.rb` records the `select` array its
    `od_select` hook is handed on a class accessor.
  - The search-recording set in `odata_duty/entity_set/search_spec.rb` records the
    `SearchExpression` its `od_search` hook receives (operator and terms) the same way.

  These show the behaviour a consumer would actually observe, so they double as documentation —
  which a mock cannot.

## Widening the allowlist is a public-API change

Adding an entry to `AllowedConstants`/`AllowedConstantPatterns` promotes a constant into the gem's
public contract. Treat it exactly like any other public API change: it goes through review, and it
implies a `doc/using_*.md` guide documenting the newly-public surface. If a spec seems to *need* a
not-yet-public constant, the question to answer first is whether that constant should be public —
not whether the allowlist should grow to accommodate one test.
