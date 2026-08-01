# Build plan — MCP read/query tools

PRD: [mcp-read-query-tools.md](mcp-read-query-tools.md)

Turns an OData set's read hooks (`collection`, `individual`, `count`) into model-invokable MCP
**tools** (`list_<Set>`, `get_<Set>`, `count_<Set>`), folds `$search` into `list_/count_<Set>`,
removes the standalone `search_<Set>` tool, and removes the MCP read resources/templates (and the
`resources` capability), making the MCP server tools-only.

Key files (both DSLs share the MCP builder):
- Shared MCP surface: `lib/odata_duty/mcp_server_builder.rb`, `lib/odata_duty/mcp_input_schemas.rb`.
- Read-hook predicates — class DSL: `lib/odata_duty.rb` (`EntitySet::Metadata`); builder DSL:
  `lib/odata_duty/schema_builder/entity_set.rb` + `schema_builder/endpoint.rb`.
- Execution reuse: `lib/odata_duty/executor.rb` (`Executor.execute` already handles
  collection / `(id)` / `/$count`); tools forward query options verbatim.
- Specs: `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/entity_set/**`.
- Docs: `doc/using_mcp.md`, `doc/using_create_update_and_delete.md`, `CLAUDE.md`.

Predicate design: add `supports_collection?` / `supports_individual?` (mirroring `supports_create?`
= `method_defined?`) to both DSLs. `list_<Set>` and `count_<Set>` gate on `collection`; `get_<Set>`
gates on `individual`; `$search` on list/count gates on the existing `supports_search?` (od_search).
These predicates are internal — exercised only through MCP `tools/list`, never tested directly.

---

## Task 1 — `list_<Set>` collection-browse tool

- [x] **Text:** Add a `list_<Set>` MCP tool, registered for every entity set that implements
  `collection`, in the shared `McpServerBuilder` (used by both DSLs). Its `inputSchema` is an object
  with optional `$filter`, `$select`, `$top` (integer), `$skip` (integer), and — only when the set
  defines `od_search` — `$search`; `required: []`. `tools/call` forwards the arguments verbatim as
  OData query options through `Executor.execute` on the collection URL and returns the collection
  JSON (same shape as `GET /<Set>`) in `result.content[0].text`. OData-level errors (malformed
  `$filter`/`$search`, `UnknownPropertyError` from `$select`, invalid query option) surface as
  tool-error results (`isError: true`), never crashing the transport. Add `supports_collection?`
  (`method_defined?(:collection)`) to the class-DSL `EntitySet::Metadata` and builder-DSL
  `EntitySet`, delegated from `SchemaBuilder::Endpoint`. Cover in **both** spec trees:
  `tools/list` shape (with and without `$search`), a `tools/call` returning collection JSON, `$top`
  narrowing, and a malformed-`$filter` tool-error. A set with no `collection` advertises no
  `list_` tool.
- **Files:** `lib/odata_duty/mcp_server_builder.rb`, `lib/odata_duty/mcp_input_schemas.rb`,
  `lib/odata_duty.rb`, `lib/odata_duty/schema_builder/entity_set.rb`,
  `lib/odata_duty/schema_builder/endpoint.rb`; new specs under both
  `spec/odata_duty/entity_set/` and `spec/odata_duty/schema_builder/entity_set/`.
- **PRD excerpt:** `list_<Set>` inputSchema block (lines 96–113); "`list_People` → the collection
  JSON (same shape as `GET /People`), inside `result.content[0].text`"; inference contract "A set
  that implements `collection` advertises `list_<Set>`"; `$search` present "only when `od_search`
  is defined"; error cases: malformed `$filter`/`$search` → `InvalidQueryOptionError` as
  `isError: true`; `$select` undefined property → `UnknownPropertyError`.
- **Depends on:** nothing.

## Task 2 — `get_<Set>` read-one-by-key tool

- [x] **Text:** Add a `get_<Set>` MCP tool, registered for every set that implements `individual`.
  `inputSchema` is an object with a required key property (same key-schema shape the `delete_<Set>`
  tool uses — `{ type: string, readOnly: true }` for a String key) plus an optional `$select`;
  `required: [<key>]`. `tools/call` runs `Executor.execute` on the `<url>('{id}')` URL, forwarding
  `$select`, and returns the individual JSON (same shape as `GET /<Set>('1')`). Missing key →
  `ResourceNotFoundError` (`No such entity <id>`) as a tool-error result; uncoercible key →
  `InvalidPropertyReferenceValue` as a tool-error result. A set with no `individual` advertises no
  `get_` tool. Add `supports_individual?` (`method_defined?(:individual)`) to both DSLs. Cover in
  **both** spec trees: `tools/list` shape, `tools/call` returning the record, not-found tool-error,
  `$select` projection, and absence of the tool for an `individual`-less set.
- **Files:** `lib/odata_duty/mcp_server_builder.rb`, `lib/odata_duty/mcp_input_schemas.rb`,
  `lib/odata_duty.rb`, `lib/odata_duty/schema_builder/entity_set.rb`,
  `lib/odata_duty/schema_builder/endpoint.rb`; new specs under both spec trees.
- **PRD excerpt:** `get_<Set>` inputSchema block (lines 116–129); "`get_People` `{ "id": "1" }` →
  the individual JSON"; inference contract "A set that implements `individual` advertises
  `get_<Set>`"; error cases lines 177–181 (`ResourceNotFoundError`, `InvalidPropertyReferenceValue`
  as tool-error results).
- **Depends on:** Task 1 (shared tool-registration plumbing).

## Task 3 — `count_<Set>` tool

- [x] **Text:** Add a `count_<Set>` MCP tool, registered for every set that implements `collection`.
  `inputSchema` is an object with optional `$filter` and — only when `od_search` is defined —
  `$search`; `required: []`. `tools/call` runs `Executor.execute` on the `<url>/$count` URL,
  forwarding `$filter`/`$search`, and returns the count as text (e.g. `"42"`) in
  `result.content[0].text`. OData-level errors surface as tool-error results. A set with no
  `collection` advertises no `count_` tool. Cover in **both** spec trees: `tools/list` shape (with
  and without `$search`), `tools/call` returning the count text, and a `$filter`-narrowed count.
- **Files:** `lib/odata_duty/mcp_server_builder.rb`, `lib/odata_duty/mcp_input_schemas.rb`; new
  specs under both spec trees.
- **PRD excerpt:** `count_<Set>` inputSchema block (lines 132–145); "`count_People` → the count as
  text (e.g. `"42"`)"; inference contract "A set that implements `collection` advertises …
  `count_<Set>`"; `$search` "only when `od_search` is defined".
- **Depends on:** Tasks 1–2 (shared plumbing; `supports_collection?`).

## Task 4 — Remove the `search_<Set>` tool

- [x] **Text:** Remove the standalone `search_<Set>` tool and `McpInputSchemas.search_input_schema`;
  `$search` capability now lives on `list_/count_<Set>`. `search_<Set>` must no longer appear in any
  `tools/list`, and a `tools/call` for `search_<Set>` returns `Unknown tool` (`-32602`). Update the
  MCP sections of both `spec/odata_duty/entity_set/search_spec.rb` and
  `spec/odata_duty/schema_builder/entity_set/search_spec.rb` (and `schema_to_mcp_server_spec.rb`)
  so they assert `$search` reaches `od_search` via `list_<Set>` (and/or `count_<Set>`) instead of
  `search_<Set>`, and that `search_<Set>` is gone. Keep the `$search` grammar tests untouched.
- **Files:** `lib/odata_duty/mcp_server_builder.rb`, `lib/odata_duty/mcp_input_schemas.rb`;
  `spec/odata_duty/entity_set/search_spec.rb`, `spec/odata_duty/entity_set/schema_to_mcp_server_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/search_spec.rb`.
- **PRD excerpt:** "`search_<Set>` is **removed** from `tools/list`; its `$search` capability now
  lives on `list_<Set>` (and `count_<Set>`)"; inference contract "`search_<Set>` is **no longer
  advertised** for any set"; Before/After table row.
- **Depends on:** Tasks 1 & 3 ($search must exist on list/count first).

## Task 5 — Remove read resources, templates, and the `resources` capability

- [x] **Text:** Remove the MCP read resources and templates and the `resources` server capability:
  drop `direct_resources`, `resource_templates`, `count_resource`, `templates_for_endpoint`,
  `register_resources_read`, and `read_resource` from `McpServerBuilder`; construct the server with
  `capabilities: { tools: {} }` and no `resources:`/`resource_templates:`. After this,
  `resources/list` and `resources/templates/list` are empty and no resources are served. Update the
  `initialize` capability expectations (`spec/odata_duty/entity_set/mcp_spec.rb`, and any builder
  equivalent) to `{ 'tools' => {} }`, and remove/replace the resources specs
  (`spec/odata_duty/entity_set/resources_mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/resources_mcp_spec.rb`) — the read behavior they
  covered is now covered by the list/get/count tool specs. Check `spec/config.ru` needs no resource
  wiring changes.
- **Files:** `lib/odata_duty/mcp_server_builder.rb`; `spec/odata_duty/entity_set/mcp_spec.rb`,
  `spec/odata_duty/entity_set/resources_mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/resources_mcp_spec.rb`.
- **PRD excerpt:** "Removed resources and tool" section (lines 156–164): `resources/list` empty,
  `resources/templates/list` empty, `resources/read` serves nothing, capabilities narrow from
  `{ tools: {}, resources: {} }` to `{ tools: {} }`; Before/After table.
- **Depends on:** Tasks 1–3 (tools must replace the resource reads first).

## Task 6 — Documentation & indexes

- [x] **Text:** Rewrite the "Resources and resource templates" section of `doc/using_mcp.md` to
  document `list_<Set>`/`get_<Set>`/`count_<Set>` under "Tools" and state the server is now
  tools-only (read resources removed); update the `initialize` capabilities example to
  `{ "tools": {} }` and the `search_<Set>` tool description to the folded-in `$search`. Add a short
  cross-reference from `doc/using_create_update_and_delete.md` describing the read→act loop
  (`list_<Set>` → pick id → `update_/delete_<Set>`). Refresh the MCP tool/resource wording in
  `CLAUDE.md`'s Architecture (`MCPExecutor`/MCP bullet) and update the **MCP server** entry in the
  `## Features` index to point at `doc/using_mcp.md` and mention tools-only reads.
- **Files:** `doc/using_mcp.md`, `doc/using_create_update_and_delete.md`, `CLAUDE.md`.
- **PRD excerpt:** "Documentation impact" section (lines 203–210).
- **Depends on:** Tasks 1–5.
