# Using MCP with OdataDuty

OdataDuty turns the schema you already defined for OData into a [Model Context
Protocol](mcp_crash_course.md) (MCP) server, so AI agents can list, read, search, and write your
entities through the same data methods that power your REST endpoints. You define the schema once;
the MCP tools are derived from it automatically. The server is **tools-only** — reads are exposed
as model-invokable tools, not MCP resources.

The MCP layer is built on the official [`mcp` Ruby SDK](https://ruby.sdk.modelcontextprotocol.io/),
which handles the JSON-RPC plumbing — lifecycle, protocol-version negotiation, capability
exchange, and spec-compliant error objects.

## Overview

- **Purpose:** expose an existing OData schema to MCP clients (e.g. the
  [MCP Inspector](https://github.com/modelcontextprotocol/inspector)) without writing any extra
  protocol code.
- **Entry point:** `schema.to_mcp_server` returns a bare `MCP::Server`. It works for **both** the
  class-based DSL (`OdataDuty::Schema`) and the builder DSL (`OdataDuty::SchemaBuilder`).
- **Transport:** mount the server over Streamable HTTP using the SDK's
  `MCP::Server::Transports::StreamableHTTPTransport`.
- **Per-request context:** the OData context (used to instantiate entity sets / resolvers and build
  URLs) is supplied at request time through the SDK's `server_context`.

## Setup

### 1. Install the dependency

`mcp` is a runtime dependency of OdataDuty and is installed automatically with the gem. If you keep
your own `Gemfile`, a plain `bundle install` after adding `odata_duty` is enough — no extra entry
is required.

### 2. Obtain a server from your schema

Both DSLs answer `to_mcp_server`. The server's `name`/`version` come from your schema's
`title`/`version`.

#### Class-based DSL

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonType
  # collection, individual, create, od_search ...
end

class MySchema < OdataDuty::Schema
  namespace 'TestSpace'
  title 'Test OData API'
  version '1.0.0'
  entity_sets PeopleSet
end

server = MySchema.to_mcp_server
```

#### Builder DSL

```ruby
schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                        scheme: 'http', base_path: '/api') do |s|
  s.title = 'Test OData API'
  s.version = '1.0.0'
  person = s.add_entity_type(name: 'Person') do |et|
    et.property_ref 'id', Integer
    et.property 'user_name', String, nullable: false
    et.property 'emails', [String], nullable: false
  end
  s.add_entity_set(url: 'People', entity_type: person, resolver: 'TestPersonResolver')
end

server = schema.to_mcp_server
```

### 3. Mount it over Streamable HTTP

In Rails, build the server per request inside a controller and hand the request to the SDK's
Streamable HTTP transport. Set `server_context` to the controller (`self`) so your entity sets /
resolvers receive it in `od_after_init`:

```ruby
class McpController < ActionController::API
  def create
    server = MySchema.to_mcp_server # builder DSL: build the schema per request, then schema.to_mcp_server
    server.server_context = { context: self }
    # No `MCP-Session-Id` is shared across requests, so run stateless.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    status, headers, body = transport.handle_request(request)
    render(json: body.first, status: status, headers: headers)
  end
end
```

```ruby
# config/routes.rb
post '/mcp' => 'mcp#create'
```

`server_context[:context]` is read back inside every tool handler and forwarded into
the normal OData execution path — it's the same `context:` you pass to `schema.execute` in your REST
controller.

A complete, runnable Rack version lives in [`spec/config.ru`](../spec/config.ru): a single Streamable
HTTP endpoint at `POST/GET/DELETE /mcp` alongside the REST endpoints. Because that demo's context is
the stateless app instance itself, it sets `server_context` once at boot rather than per request.

### 4. Point an MCP client at it

With the dev server running (`bundle exec rerun -- bundle exec rackup spec/config.ru`), launch the
inspector against the endpoint:

```bash
npx @modelcontextprotocol/inspector@0.15.0 -e PORT=9292 bundle exec rackup spec/config.ru
```

## What the schema produces

`to_mcp_server` derives the MCP tool surface from your schema — you do not register tools by hand.
The server is tools-only; it advertises no MCP resources.

### Tools

Reads are exposed as tools (inferred from the read data methods), so an agent can complete a full
loop through tools alone: `list_<Set>` to find records, then `get_/update_/delete_<Set>` by a
discovered key.

- **`list_<Set>`** — registered for every set that implements `collection`. Its input schema is
  all-optional (`required: []`): `$filter`, `$select`, `$top` (integer), `$skip` (integer), and —
  only when the set defines [`od_search`](using_search.md) — `$search`. Calling it runs the same
  execution as `GET /<Set>` and returns the collection JSON.
- **`get_<Set>`** — registered for every set that implements `individual`. Its input schema is the
  entity key property (`required`) plus an optional `$select`. Calling it returns the individual
  JSON (same shape as `GET /<Set>('1')`). A not-found or uncoercible key is returned as a
  tool-error result (`isError: true`).
- **`count_<Set>`** — registered for every set that implements `collection`. Its input schema is
  all-optional (`required: []`): `$filter`, and — only when the set defines `od_search` — `$search`.
  Calling it returns the count as text (e.g. `"42"`).
- **`create_<Set>`** — registered for every writable set (one that implements
  [`create`](using_create_update_and_delete.md)). Its input schema is built from the entity type's
  properties; non-nullable properties become `required`.
- **`update_<Set>` / `delete_<Set>`** — registered for sets that implement `update` / `delete` — see
  [`using_create_update_and_delete.md`](using_create_update_and_delete.md).

`tools/list` returns these with their derived names, descriptions, and input schemas. A successful
`tools/call` returns the result inside a text content block (`result.content[0].text`) — the
collection/individual JSON for `list_`/`get_`, the numeric count as text for `count_`.

### No MCP resources (tools-only)

The server is tools-only: it does **not** register MCP resources or resource templates, and its
`initialize` capabilities advertise only `{"tools":{}}`. Reads that were previously served as
resources (individual-by-id, paginated collection, `/$count`) are now served by the `list_<Set>`,
`get_<Set>`, and `count_<Set>` tools above. Because the `resources` capability is no longer
advertised, the SDK rejects `resources/list`, `resources/templates/list`, and `resources/read` with
a JSON-RPC error.

## Protocol-version negotiation

`initialize` negotiates the protocol version through the SDK rather than pinning a fixed revision.
If the client requests a supported version, the server echoes it back; if it requests an
unsupported one, the server responds with its latest supported version.

Request:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize",
 "params":{"protocolVersion":"2025-06-18","capabilities":{},
           "clientInfo":{"name":"inspector","version":"0.15.0"}}}
```

Response:

```json
{"jsonrpc":"2.0","id":1,"result":{
  "protocolVersion":"2025-06-18",
  "capabilities":{"tools":{}},
  "serverInfo":{"name":"Test OData API","version":"1.0.0"}}}
```

## Common Error Cases

The server returns spec-compliant JSON-RPC error objects instead of crashing the transport with an
HTTP 500:

- **Unknown method** → JSON-RPC `-32601` (method not found).
- **Unknown tool, or a `create_`/`update_`/`delete_` on a set lacking that capability** →
  JSON-RPC `-32602` (invalid params) — such tools are simply not registered.
- **`resources/list`, `resources/templates/list`, or `resources/read`** → rejected with a JSON-RPC
  error: the server is tools-only and no longer advertises the `resources` capability.
- **OData-level errors during a `list_`/`get_`/`count_`/`create_`/... tool call** (e.g. a `$search`
  parse error, an `InvalidQueryOptionError`, or a `ResourceNotFoundError` for a missing `get_` key)
  → returned as a tool-error result (`isError: true`) whose content carries the error message,
  rather than crashing the transport.
