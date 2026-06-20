# Build plan: MCP on the official Ruby SDK

PRD: [task-tgxix6fq7dGdMEYHml.md](./task-tgxix6fq7dGdMEYHml.md)

## Context & design decisions (resolving the PRD's open questions)

The official `mcp` gem (v0.20.0) is installable in this environment. `require 'mcp'` is
lean — it does NOT pull `faraday`/`rack`; the `StreamableHTTPTransport` autoloads `rack`
only when referenced, and `rack` is already a dev dependency.

Key SDK facts discovered:

- `MCP::Server.new(name:, version:, capabilities:, tools:, resources:, resource_templates:,
  server_context:, configuration:)`. `handle_json(json_string, session: nil)` → JSON string
  (or `nil` for notifications). This is the public API our specs drive.
- `initialize` negotiates: echoes the requested `protocolVersion` if it is in
  `MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS`
  (`2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`); otherwise returns the server's
  configured latest (`2025-11-25`). Matches the PRD's negotiation requirement.
- Unknown **method** → `-32601` (free from the SDK / `JsonRpcHandler`). Unknown **tool** →
  `-32602` (`RequestHandlerError invalid_params`, message `"Tool not found: <name>"`).
- `MCP::Tool::InputSchema#to_h` injects `"$schema":
  "https://json-schema.org/draft/2020-12/schema"` and uses the SDK's serialization. So
  `tools/list` `inputSchema` gains a `$schema` key vs. the old hand-rolled output — an
  accepted SDK-driven shape change (the PRD's JSON examples are illustrative; "code wins").
- `tools/call` returns `MCP::Tool::Response#to_h` = `{content: [{type:'text', text: …}],
  isError: false}`. The OData JSON is the `text` of a text content block — NOT the bare
  `result` as before. Accepted SDK-driven shape change.
- The SDK's unconditional `missing_required_arguments?` check means a `create_<Set>` tool
  whose `inputSchema.required` includes a field will reject a `tools/call` omitting it (as a
  tool-error result). New `create` tool-call specs therefore pass all required fields. This
  is protocol-layer input validation, not a change to OData `create` semantics (out of scope).
- Per-request context: handlers read the OData context out of the SDK `server_context`
  (a Hash `{ context: <odata ctx> }`); inside a handler the SDK wraps it in
  `MCP::ServerContext`, which delegates `[]` to the underlying Hash via `method_missing`, so
  `server_context[:context]` yields the OData context. `to_mcp_server` returns a bare
  `MCP::Server`; consumers set `server.server_context = { context: ctx }` per request (specs
  do this; `spec/config.ru` sets it once because its context is the stateless app instance).
- Capabilities advertised: `{ tools: {}, resources: {} }` (matches the PRD initialize
  example). These satisfy the SDK capability gate for `tools/*` and `resources/*`.

**Shared implementation.** Like the existing `MCPExecutor`, the new server builder is written
ONCE against the common endpoint interface (`schema.endpoints` → objects with `name`, `url`,
`entity_type`, `supports_search?`, `supports_create?`; plus `schema.title`/`schema.version`)
that BOTH DSLs already expose, then surfaced as `to_mcp_server` on both
`OdataDuty::Schema` (class DSL) and `OdataDuty::SchemaBuilder::Schema` (builder DSL).

**Out of scope (per PRD §8):** the `doc/using_mcp.md` guide and README doc updates are
"not part of this PRD's output" — no docs task. `spec/config.ru` transport migration IS in
scope (§7 "Streamable HTTP in the canonical example").

---

## Tasks

### Task 1 — Foundation: `mcp` dependency, shared server builder, `to_mcp_server`, protocol negotiation
- [x] **1**

Add `mcp` as a runtime dependency (`odata_duty.gemspec`, then `bundle install`). Create a
shared `OdataDuty::McpServerBuilder` (new `lib/odata_duty/mcp_server_builder.rb`, required
from `lib/odata_duty.rb`) that builds an `MCP::Server` with `name: schema.title`,
`version: schema.version`, and `capabilities: { tools: {}, resources: {} }`. Add
`to_mcp_server` to BOTH `OdataDuty::Schema` and `OdataDuty::SchemaBuilder::Schema`,
delegating to the builder. (Tools/resources are wired in Tasks 2–3; this task only needs the
server, serverInfo, capabilities, and the SDK's built-in `initialize`/`notifications`/
unknown-method handling.)

Likely files: `odata_duty.gemspec`, `lib/odata_duty.rb`,
`lib/odata_duty/mcp_server_builder.rb` (new), `lib/odata_duty/schema_builder.rb`.
Specs (BOTH trees): rewrite the `initialize` + `notifications/initialized` examples in
`spec/odata_duty/schema_builder_spec.rb` to use `schema.to_mcp_server` and
`server.handle_json`; ADD a sibling class-DSL spec (e.g.
`spec/odata_duty/entity_set/mcp_spec.rb`) covering the same.

Definition of done (PRD §5): `initialize` with `protocolVersion:"2025-06-18"` →
`result.protocolVersion=="2025-06-18"`, `capabilities=={"tools":{},"resources":{}}`,
`serverInfo=={"name"=>schema.title,"version"=>schema.version}`. Unsupported requested version
→ server's latest supported version. Unknown method → JSON-RPC `-32601`.
`notifications/initialized` → no response (nil).

Depends on: none.

### Task 2 — Tools: `search_<Set>` / `create_<Set>` registration, `tools/list`, `tools/call`, error compliance
- [ ] **2**

In the shared builder, register one `search_<Set>` tool per endpoint with `supports_search?`
and one `create_<Set>` tool per endpoint with `supports_create?` — same names
(`search_<Name>` / `create_<Name>`), descriptions
(`"Search <Name> using expressions with AND, OR, NOT operators"` /
`"Create a new <Name> record"`), and input schemas (search: `$search` string required;
create: entity-type properties via `to_oas2`, non-nullable → required) as today. Tool
handlers delegate to `Executor.execute` / `Executor.create` using the OData context from
`server_context[:context]`, forwarding the tool `arguments` as `query_options` unchanged, and
return the OData JSON as a text content block. OData-level errors (e.g. search-expression
parse errors, `InvalidQueryOptionError`) are rescued and returned as a tool-error result
(`isError: true`) rather than crashing. Unknown/unsupported tools are simply not registered →
SDK returns `-32602`.

Likely files: `lib/odata_duty/mcp_server_builder.rb`.
Specs (BOTH trees): rewrite the `mcp` tool sections in
`spec/odata_duty/entity_set/search_spec.rb`, `spec/odata_duty/entity_set/create/mcp_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/search_spec.rb`,
`spec/odata_duty/schema_builder/entity_set/create/mcp_spec.rb` to use `to_mcp_server` +
`handle_json`, asserting: `tools/list` shapes (names/descriptions/inputSchema incl. SDK
`$schema`, `required`); `tools/call` success returns the OData collection JSON inside
`result.content[0].text`; calling an unknown tool, a `search_` on a non-searchable set, or a
`create_` on a read-only set → JSON-RPC `-32602`; a search parse error → tool-error result.

Definition of done (PRD §5 tools/list & tools/call; §6 unknown tool → `-32602`,
OData errors surfaced not crashing).

Depends on: Task 1.

### Task 3 — Resources: `resources/list`, `resources/templates/list`, `resources/read`
- [ ] **3**

In the shared builder, register per endpoint: an individual-by-id resource template
(`<url>('{id}')`, name = entity-type name, "Retrieve a specific <EntityType> record by ID",
`application/json`); a paginated-collection template (`<url>?$top={top}&$skip={skip}`,
name "Paginated <Name> Collection", `application/json`); and a `<url>/$count` resource
(name "<Name> Count", `text/plain`) — same URIs/shapes as today. Set a
`resources_read_handler` that parses the requested `uri`, runs `Executor.execute` with the
OData context from `server_context[:context]` and any query options, and returns
`[{ uri:, mimeType: 'application/json', text: <odata json> }]`. Surface OData lookup errors
through the MCP response rather than crashing.

Likely files: `lib/odata_duty/mcp_server_builder.rb`.
Specs (BOTH trees): rewrite the resources sections in
`spec/odata_duty/schema_builder_spec.rb` (`resources/list`, `resources/templates/list`,
`resources/read`) to use `to_mcp_server` + `handle_json`; ADD class-DSL siblings (in the
Task-1 class-DSL mcp spec or a dedicated file).

Definition of done (PRD §5 resources shapes; §6 OData errors surfaced not crashing).

Depends on: Task 1 (and shares the builder with Task 2).

### Task 4 — Remove the legacy path; migrate the canonical example to Streamable HTTP
- [ ] **4**

Remove the old `handle_jsonrpc` entry point from both DSLs and delete
`lib/odata_duty/mcp_executor.rb` (+ its `require`) and the now-dead skipped `tool.invoke`
examples. Migrate `spec/config.ru` to mount the official `StreamableHTTPTransport` over
`schema.to_mcp_server` (single Streamable-HTTP endpoint; drop the old `/events`
`endpoint`-event + separate `/jsonrpc` POST SSE flow). Ensure no `handle_jsonrpc` /
`MCPExecutor` references remain anywhere and the full suite + RuboCop are green.

Likely files: `lib/odata_duty.rb`, `lib/odata_duty/schema_builder.rb`,
`lib/odata_duty/mcp_executor.rb` (delete), `spec/config.ru`, plus any spec still referencing
`handle_jsonrpc`.

Definition of done (PRD §3 compat break accepted; §5 Transport; §7 Streamable HTTP in the
canonical example).

Depends on: Tasks 1–3 (all `handle_jsonrpc`-based specs must already be migrated).
