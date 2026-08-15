---
paths: ["spec/**"]
---

# Specs are public documentation

Write specs as human-readable usage examples: real named classes and schemas defined the way a
consumer would write them, exercised through the public API, with `describe`/`it` descriptions
explaining the case each example helps with. Convey intent through those descriptions, not through
explanatory `#` comments.

**Use only the gem's public API.** That surface is:

- the schema-definition DSL (class macros / builder methods) and the errors it raises at definition
  time;
- `Schema.execute` / `.create` / `.update` / `.delete` (or the builder equivalents) and the
  JSON/XML they produce;
- `metadata_xml` / `index_hash`;
- `OAS2.build_json`;
- `to_mcp_server` plus its JSON-RPC calls (`initialize`, `tools/list`, `tools/call`).

No stubbing (`stub_const`, mocks) of gem internals. If a behaviour can only be shown with test
machinery, question the behaviour instead.

**Why:** these specs double as the gem's documentation and as its compatibility contract. A spec
that reaches past the public API pins an implementation detail, blocking refactors while proving
nothing a consumer can rely on.

## Verify

Every assertion runs against rendered output or a public entry point, the schema classes read like
something a consumer would actually write, and no `stub_const`/mock touches gem internals.
