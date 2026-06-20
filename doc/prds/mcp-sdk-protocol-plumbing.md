# PRD: MCP on the official Ruby SDK — protocol plumbing only

## 1. Summary

Rebuild OdataDuty's MCP surface on the official [`mcp` Ruby SDK](https://ruby.sdk.modelcontextprotocol.io/)
so the JSON-RPC plumbing — lifecycle, protocol-version negotiation, capabilities, and error
semantics — is spec-compliant and maintained upstream, while the *schema-derived* MCP surface
(resources, resource templates, and `search_`/`create_` tools generated from the OData schema)
stays the consumer's value. For gem consumers exposing an OData schema to AI agents.

## 2. Goal / Problem

Today the MCP surface is hand-rolled. Observable consequences:

- **Stale protocol.** `initialize` always returns `protocolVersion: "2024-11-05"` regardless of
  what the client requests — no negotiation. Current clients expect a current revision.
- **Non-compliant errors.** Unknown tools/methods `raise`, which the example Rack app turns into
  HTTP 500s. There is no way to return a JSON-RPC error object
  (`{ "error": { "code", "message" } }`).
- **Deprecated transport.** The canonical example (`spec/config.ru`) demonstrates the old HTTP+SSE
  transport (an `endpoint` event plus a separate POST channel) rather than Streamable HTTP.

Expected after this change: the MCP endpoint negotiates protocol version, returns spec-compliant
JSON-RPC errors, and the canonical example uses Streamable HTTP — with the exposed tools/resources
unchanged in meaning.

## 3. What it enables

- *As a gem consumer, I can* point any current MCP client (e.g. the MCP Inspector) at my
  OData-backed schema and have `initialize` negotiate a supported protocol version instead of being
  pinned to a 2024 revision.
- *As a gem consumer, I can* rely on malformed or unknown tool calls coming back as JSON-RPC error
  objects my client understands, not opaque 500s.
- *As a gem consumer, I can* mount the MCP server over Streamable HTTP following the canonical
  example, and still get the same `search_<Set>` / `create_<Set>` tools and resource templates
  derived from my schema.

**Scope limit:** This does **not** add new MCP primitives (prompts, structured/`structuredContent`
tool output, sampling, completions) — the tool/resource *mapping* is preserved as-is.
**Compatibility break is accepted:** the existing `handle_jsonrpc(request_hash, context:)` entry
point may be removed/replaced, since it isn't relied on externally.

## 4. External API

The consumer-facing entry point changes. Today both DSLs expose `handle_jsonrpc`; this PRD replaces
it with a method that yields an MCP server object the consumer mounts over Streamable HTTP.
Per-request context is threaded through at request time.

### Class-based DSL

```ruby
class PeopleSet < OdataDuty::EntitySet
  # ... entity_type, collection, individual, create, od_search ...
end

class MySchema < OdataDuty::Schema
  namespace 'TestSpace'
  entity_sets PeopleSet
end

# In a Rack handler:
server = MySchema.to_mcp_server                       # tools/resources derived from the schema
transport = MCP::Server::Transports::StreamableHTTPTransport.new(server)
transport.handle(request, server_context: { context: my_request_context })
```

### Builder DSL

```ruby
schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                        scheme: 'http', base_path: '/api') do |s|
  person = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', Integer }
  s.add_entity_set(url: 'People', entity_type: person, resolver: 'TestPersonResolver')
end

server = schema.to_mcp_server
# ... same Streamable HTTP wiring as above ...
```

### Contract of `to_mcp_server`

- Returns an `MCP::Server` (official SDK) whose `name`/`version` come from `schema.title` /
  `schema.version`.
- Registers one `search_<Set>` tool per entity set whose resolver defines `od_search`, and one
  `create_<Set>` tool per writable set — same names, descriptions, and input schemas as today
  (`$search` string input; create input schema from entity-type properties with non-nullable →
  required).
- Registers resources and resource templates per endpoint: individual-by-id template,
  paginated-collection template, and a `/$count` resource — same URIs/shapes as today.
- The per-request OData context (used to instantiate resolvers and URL helpers) is supplied by the
  consumer at request time via the SDK's `server_context` and forwarded into OData execution.
  Tool/resource handlers continue to delegate to the existing OData execution path, forwarding
  OData query options (`$search`, `$top`, `$skip`, create body) unchanged.

## 5. Behavior & expected I/O

### Version negotiation — `initialize`

Request:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize",
 "params":{"protocolVersion":"2025-06-18","capabilities":{},
           "clientInfo":{"name":"inspector","version":"0.15.0"}}}
```

Response (echoes a supported version instead of a hardcoded 2024 string):

```json
{"jsonrpc":"2.0","id":1,"result":{
  "protocolVersion":"2025-06-18",
  "capabilities":{"tools":{},"resources":{}},
  "serverInfo":{"name":"Test OData API","version":"1.0.0"}}}
```

If the client requests an unsupported version, the server responds with its latest supported
version (SDK negotiation behavior), rather than ignoring the field.

### `tools/list` — unchanged shapes

```json
{"jsonrpc":"2.0","id":2,"result":{"tools":[
  {"name":"search_People","description":"Search People using expressions with AND, OR, NOT operators",
   "inputSchema":{"type":"object","properties":{"$search":{"type":"string","description":"..."}},"required":["$search"]}},
  {"name":"create_People","description":"Create a new People record","inputSchema":{"type":"object","properties":{},"required":["user_name","emails"]}}
]}}
```

### `tools/call` success

`search_People` with `{"$search":"john"}` returns the same OData collection JSON wrapped as MCP
tool content as today.

### Error compliance (before → after)

Calling an unknown tool:

- *Before:* `raise "Unknown tool: foo"` → example app emits HTTP `500 {"error":"Internal Server Error"}`.
- *After:* JSON-RPC error object:

```json
{"jsonrpc":"2.0","id":5,"error":{"code":-32602,"message":"Unknown tool: foo"}}
```

### Transport

The canonical `spec/config.ru` demonstrates Streamable HTTP (single endpoint handling POST +
streamed responses) instead of the `endpoint`-event + separate-POST SSE flow.

## 6. Common error cases

- **Unknown method** → JSON-RPC `-32601` (method not found), not a raise/500.
- **Unknown tool / bad tool arguments** → JSON-RPC `-32602` (invalid params).
- **OData-level errors during a tool/resource call** (e.g. `ResourceNotFoundError`,
  `InvalidQueryOptionError`, `NoImplementationError`) → surfaced through the MCP response (as a tool
  error result / JSON-RPC error) rather than crashing the transport with a 500.

## 7. Scope

- **In:** MCP JSON-RPC/protocol layer rebuilt on the official `mcp` gem; protocol-version
  negotiation; spec-compliant JSON-RPC errors; Streamable HTTP in the canonical example; **both
  DSLs** (class-based + builder); preservation of the schema→tool/resource mapping (names,
  descriptions, input schemas, URIs).
- **Out:** new MCP primitives (prompts, structured output, sampling, completions); any change to
  OData/EDMX/OAS2 outputs or to `od_search`/`create`/`od_filter_*` semantics; backward
  compatibility of the old `handle_jsonrpc` entry point.

## 8. Documentation impact

Add a new consumer guide **`doc/using_mcp.md`** (purpose-first, example-driven, ending in "Common
Error Cases"): how to obtain a server via `to_mcp_server`, mount it over Streamable HTTP, which
tools/resources the schema produces, and the error contract. Update the README's MCP references and
`spec/config.ru` comments to point at it. (Documentation written only on request — not part of this
PRD's output.)

## 9. Open questions

- **Entry-point name/return:** `to_mcp_server` vs `mcp_server`/`build_mcp_server`; return a bare
  `MCP::Server` vs a ready-mounted Rack app. Also whether to keep a thin one-shot
  `handle(request_hash, context:)` convenience for non-HTTP/stdio use.
- **Context threading:** SDK `server_context` passed per request vs rebuilding a server per request
  — which integrates more cleanly with OdataDuty's per-request resolver instantiation.
- **Dependency posture:** `mcp` (and its HTTP-transport deps `faraday`/`event_stream_parser`) as a
  hard runtime dependency vs optional/lazy-required, given the gem's deliberately lean, "no Rails
  required" footprint.
- **Minimum supported protocol version** to advertise during negotiation.
