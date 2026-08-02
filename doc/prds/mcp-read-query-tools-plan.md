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

Predicate design: `supports_collection?` / `supports_individual?` (mirroring `supports_create?`
= `method_defined?`) added to both DSLs. `list_<Set>` and `count_<Set>` gate on `collection`;
`get_<Set>` gates on `individual`; `$search` on list/count gates on the existing `supports_search?`
(od_search). These predicates are internal — exercised only through MCP `tools/list`, never tested
directly.

Order note: resource removal (Task 2) runs right after `list_<Set>` to free ModuleLength headroom
in `McpServerBuilder` before the `get_`/`count_` tool methods are added.

Mutant note: the MCP registration/input-schema methods can't be mutation-tested through the
`MCP::Server` build path — every sibling is already ignore-listed in `.mutant.yml`. Per the repo
ratchet rule, no new `.mutant.yml` entries are added; the new methods' mutant survivors are a known
tooling limitation, flagged to the user at the end rather than papered over.

---

## Task 1 — `list_<Set>` collection-browse tool

- [x] **Text:** Add a `list_<Set>` MCP tool, registered for every entity set that implements
  `collection`, in the shared `McpServerBuilder` (used by both DSLs). Its `inputSchema` is an object
  with optional `$filter`, `$select`, `$top` (integer), `$skip` (integer), and — only when the set
  defines `od_search` — `$search`; `required: []`. `tools/call` forwards the arguments verbatim as
  OData query options through `Executor.execute` on the collection URL and returns the collection
  JSON (same shape as `GET /<Set>`) in `result.content[0].text`. OData-level errors surface as
  tool-error results (`isError: true`). Add `supports_collection?` to both DSLs. Cover in both spec
  trees.
- **Files:** `mcp_server_builder.rb`, `mcp_input_schemas.rb`, `lib/odata_duty.rb`,
  `schema_builder/entity_set.rb`, `schema_builder/endpoint.rb`; new list specs in both trees.
- **PRD excerpt:** `list_<Set>` inputSchema block (lines 96–113); collection-JSON result; inference
  "implements `collection` advertises `list_<Set>`"; `$search` only when `od_search`; error cases.
- **Depends on:** nothing.

## Task 2 — Remove read resources, templates, and the `resources` capability

- [x] **Text:** Remove the MCP read resources and templates and the `resources` server capability:
  drop `direct_resources`, `resource_templates`, `count_resource`, `templates_for_endpoint`, and
  `read_resource` (and the `resources_read_handler`) from `McpServerBuilder`; construct the server
  with `capabilities: { tools: {} }` and no `resources:`/`resource_templates:`. After this,
  `resources/list` and `resources/templates/list` are empty and no resources are served. With the
  freed headroom, restore `register_update_tool`/`register_delete_tool` as clean named methods (undo
  Task 1's inlining) so the tool-registration block reads cleanly. Update the `initialize`
  capability expectations to `{ 'tools' => {} }` in `spec/odata_duty/entity_set/mcp_spec.rb` (and
  any builder equivalent); remove the resources specs
  (`spec/odata_duty/entity_set/resources_mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/resources_mcp_spec.rb`) — their read behavior is now
  covered by the list tool spec (and, in later tasks, get/count); update the resource-template
  assertions in `spec/odata_duty/entity_set/schema_to_mcp_server_spec.rb`. Prune any now-stale
  `.mutant.yml` entries for methods deleted here (`register_resources_read`). Confirm `spec/config.ru`
  needs no resource wiring changes. Ensure `bundle exec rake` stays green with 100% coverage.
- **Files:** `mcp_server_builder.rb`, `.mutant.yml`; `spec/odata_duty/entity_set/mcp_spec.rb`,
  `spec/odata_duty/entity_set/resources_mcp_spec.rb`,
  `spec/odata_duty/entity_set/schema_to_mcp_server_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/resources_mcp_spec.rb`.
- **PRD excerpt:** "Removed resources and tool" (lines 156–164): `resources/list` empty,
  `resources/templates/list` empty, `resources/read` serves nothing, capabilities narrow from
  `{ tools: {}, resources: {} }` to `{ tools: {} }`; Before/After table.
- **Depends on:** Task 1.

## Task 3 — `get_<Set>` read-one-by-key tool

- [x] **Text:** Add a `get_<Set>` MCP tool, registered for every set that implements `individual`.
  `inputSchema` is an object with a required key property (same key-schema shape the `delete_<Set>`
  tool uses — `{ type: string, readOnly: true }` for a String key) plus an optional `$select`;
  `required: [<key>]`. `tools/call` runs `Executor.execute` on the `<url>('{id}')` URL, forwarding
  `$select`, and returns the individual JSON (same shape as `GET /<Set>('1')`). Missing key →
  `ResourceNotFoundError` (`No such entity <id>`) as a tool-error result; uncoercible key →
  `InvalidPropertyReferenceValue` as a tool-error result. A set with no `individual` advertises no
  `get_` tool. Add `supports_individual?` (`method_defined?(:individual)`) to both DSLs. Cover in
  both spec trees.
- **Files:** `mcp_server_builder.rb`, `mcp_input_schemas.rb`, `lib/odata_duty.rb`,
  `schema_builder/entity_set.rb`, `schema_builder/endpoint.rb`; new get specs in both trees.
- **PRD excerpt:** `get_<Set>` inputSchema block (lines 116–129); "`get_People` `{ "id": "1" }` →
  the individual JSON"; inference "implements `individual` advertises `get_<Set>`"; error cases
  lines 177–181 (`ResourceNotFoundError`, `InvalidPropertyReferenceValue` as tool-error results).
- **Depends on:** Tasks 1–2 (shared plumbing; freed headroom).

## Task 4 — `count_<Set>` tool

- [x] **Text:** Add a `count_<Set>` MCP tool, registered for every set that implements `collection`.
  `inputSchema` is an object with optional `$filter` and — only when `od_search` is defined —
  `$search`; `required: []`. `tools/call` runs `Executor.execute` on the `<url>/$count` URL,
  forwarding `$filter`/`$search`, and returns the count as text (e.g. `"42"`) in
  `result.content[0].text`. OData-level errors surface as tool-error results. A set with no
  `collection` advertises no `count_` tool. Cover in both spec trees: `tools/list` shape (with and
  without `$search`), `tools/call` returning the count text, and a `$filter`-narrowed count.
- **Files:** `mcp_server_builder.rb`, `mcp_input_schemas.rb`; new count specs in both trees.
- **PRD excerpt:** `count_<Set>` inputSchema block (lines 132–145); "`count_People` → the count as
  text"; inference "implements `collection` advertises … `count_<Set>`"; `$search` only when
  `od_search`.
- **Depends on:** Tasks 1–3.

## Task 5 — Remove the `search_<Set>` tool

- [x] **Text:** Remove the standalone `search_<Set>` tool and `McpInputSchemas.search_input_schema`;
  `$search` now lives on `list_/count_<Set>`. `search_<Set>` must no longer appear in any
  `tools/list`, and a `tools/call` for `search_<Set>` returns `Unknown tool` (`-32602`). Update the
  MCP sections of both `spec/odata_duty/entity_set/search_spec.rb` and
  `spec/odata_duty/schema_builder/entity_set/search_spec.rb` (and any remaining
  `schema_to_mcp_server_spec.rb` assertion) so they assert `$search` reaches `od_search` via
  `list_<Set>` (and/or `count_<Set>`) instead of `search_<Set>`, and that `search_<Set>` is gone.
  Keep the `$search` grammar tests untouched. Prune the now-stale `.mutant.yml` entries for
  `register_search_tool` and `search_input_schema`.
- **Files:** `mcp_server_builder.rb`, `mcp_input_schemas.rb`, `.mutant.yml`;
  `spec/odata_duty/entity_set/search_spec.rb`,
  `spec/odata_duty/entity_set/schema_to_mcp_server_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/search_spec.rb`.
- **PRD excerpt:** "`search_<Set>` is **removed** from `tools/list`; its `$search` capability now
  lives on `list_<Set>` (and `count_<Set>`)"; inference "`search_<Set>` is **no longer advertised**";
  Before/After table.
- **Depends on:** Tasks 1, 4 ($search must exist on list/count first).

## Task 6 — Documentation & indexes

- [ ] **Text:** Rewrite the "Resources and resource templates" section of `doc/using_mcp.md` to
  document `list_<Set>`/`get_<Set>`/`count_<Set>` under "Tools" and state the server is now
  tools-only (read resources removed); update the `initialize` capabilities example to
  `{ "tools": {} }` and the `search_<Set>` tool description to the folded-in `$search`. Add a short
  cross-reference from `doc/using_create_update_and_delete.md` describing the read→act loop
  (`list_<Set>` → pick id → `update_/delete_<Set>`). Refresh the MCP tool/resource wording in
  `CLAUDE.md`'s Architecture (`MCPExecutor`/MCP bullet) and update the **MCP server** entry in the
  `## Features` index to point at `doc/using_mcp.md` and mention tools-only reads.
- **Files:** `doc/using_mcp.md`, `doc/using_create_update_and_delete.md`, `CLAUDE.md`.
- **PRD excerpt:** "Documentation impact" (lines 203–210).
- **Depends on:** Tasks 1–5.
