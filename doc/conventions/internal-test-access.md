---
paths: ["spec/**"]
contents: ['__metadata|stub_const|\.to_oas2\b|\.to_value\b|\.mapper\b|Wrapper|Endpoint']
---

# Don't reach into internals from a spec

This spec touches something outside the public API. Common traps:

- `__metadata` on a schema/type/set;
- any `*Wrapper` or `Endpoint` object;
- calling `.to_oas2` / `.to_value` / `.mapper` on a type or property object directly;
- `stub_const` or a mock standing in for a gem internal.

A DSL macro's own reader (e.g. `PersonEntity.description`) is **not** proof a value propagated —
it only proves the macro stored it. Assert against the rendered output instead: `$metadata` XML,
`$oas2` JSON, the executed JSON response, or the MCP `tools/list` / `tools/call` result.

**Why:** internals are renamed and restructured freely; only the rendered output is promised to
consumers. A spec asserting on internals passes while the user-visible behaviour is broken, and
fails on refactors that broke nothing.

This is enforced by two layers, not just advised — see `spec/using_public_api_only.md`. The
`OdataDuty/PublicApiOnly` RuboCop cop fails the build on an internal constant, a `__`-prefixed method
call, a visibility bypass, or a mock. The cop can't see a reader called on a locally-held gem object
(no type inference); that case is caught at runtime by the guard (`spec/support/public_api_guard.rb`),
which knows the receiver's class and raises `NonPublicApiError` for an internal method on a gem
object.

## Verify

Replace the internal call with an assertion on `metadata_xml`, `OAS2.build_json`,
`Schema.execute`/`.create`/`.update`/`.delete`, or an MCP JSON-RPC response — or confirm the match
was incidental (e.g. the word appears in a `describe` string).
