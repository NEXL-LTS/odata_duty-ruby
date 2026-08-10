---
paths: ["lib/**"]
---

# Architecture / request flow

A schema is just metadata until executed. Both DSLs expose `__metadata` objects that the renderers
and executor walk.

- **`Executor`** (`executor.rb`) is the core of GET. It resolves a URL to an endpoint, instantiates
  the set builder/resolver, then dispatches on the URL/query: `(id)` → individual, `/$count` →
  count, otherwise collection. It applies `$filter` (→ `od_filter_eq/ne/gt/lt`, see `filter.rb`),
  `$select`, `$search`, and `$top`/`$skip` paging. `Schema.execute` / `.create` delegate here.
- **`McpServerBuilder`** (`mcp_server_builder.rb`, input schemas in `mcp_input_schemas.rb`) builds a
  tools-only `MCP::Server` (`schema.to_mcp_server`); the SDK handles the JSON-RPC. Reads become
  `list_/count_/get_<Set>`, writes `create_/update_/delete_<Set>`. Every tool reuses `Executor`
  underneath — OData query options are forwarded. No MCP resources are registered.
- **Renderers**: `EdmxSchema` (`metadata_xml` via `lib/metadata.xml.erb`, `index_hash`) and `OAS2`
  (`oas2.rb` + `oas2/*_path.rb`) produce the `$metadata`, index, and `$oas2` documents.
- **`*Wrapper` classes** isolate user-supplied objects: `ContextWrapper` (per-request context + URL
  helpers), `CreateComplexTypeHashWrapper` (coerces/validates POST bodies), and
  `dynamic_object_wrapper.rb.erb` / `mapper_builder.rb` (per-entity object→hash mappers).
- **`parslet_search_expression.rb`** parses the `$search` grammar into an expression object passed
  to a resolver's `od_search`.

**Why:** new behaviour almost always belongs on one of these seams rather than in a new top-level
class — features reach `$metadata`, `$oas2`, and MCP only by going through the executor and
renderers above.
