# Using MCP with OdataDuty

OdataDuty turns the schema you already defined for OData into a [Model Context
Protocol](mcp_crash_course.md) (MCP) server, so AI agents can search, read, and create your
entities through the same data methods that power your REST endpoints. You define the schema once;
the MCP tools and resources are derived from it automatically.

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

`server_context[:context]` is read back inside every tool and resource handler and forwarded into
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

`to_mcp_server` derives the MCP surface from your schema — you do not register tools or resources
by hand.

### Tools

- **`search_<Set>`** — registered for every entity set whose resolver/set defines
  [`od_search`](using_search.md). Its input schema requires a single `$search` string. Calling it
  runs the same `$search` execution as the OData endpoint and returns the collection JSON.
- **`create_<Set>`** — registered for every writable set (one that implements
  [`create`](using_create.md)). Its input schema is built from the entity type's properties;
  non-nullable properties become `required`.

`tools/list` returns these with their derived names, descriptions, and input schemas. A successful
`tools/call` returns the OData JSON inside a text content block
(`result.content[0].text`).

### Resources and resource templates

Per entity set, the server registers:

- an **individual-by-id** template — `<url>('{id}')`,
- a **paginated-collection** template — `<url>?$top={top}&$skip={skip}`, and
- a **`<url>/$count`** resource (`text/plain`).

`resources/read` parses the requested URI, runs it through the same OData execution path, and
returns the result as the resource `text`. The `mimeType` matches what `resources/list` advertised:
`text/plain` for `/$count`, `application/json` otherwise.

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
  "capabilities":{"tools":{},"resources":{}},
  "serverInfo":{"name":"Test OData API","version":"1.0.0"}}}
```

## Common Error Cases

The server returns spec-compliant JSON-RPC error objects instead of crashing the transport with an
HTTP 500:

- **Unknown method** → JSON-RPC `-32601` (method not found).
- **Unknown tool, a `search_` on a non-searchable set, or a `create_` on a read-only set** →
  JSON-RPC `-32602` (invalid params) — such tools are simply not registered.
- **OData-level errors during a tool call** (e.g. a `$search` parse error, an
  `InvalidQueryOptionError`) → returned as a tool-error result (`isError: true`) whose content
  carries the error message, rather than crashing the transport.
- **OData-level errors during a resource read** (e.g. `ResourceNotFoundError`) → surfaced through
  the `resources/read` response as `text/plain` text rather than crashing.
