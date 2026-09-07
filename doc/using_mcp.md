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
  all-optional (`required: []`) and advertises only the query options the set can actually serve
  (see *Query options on the read tools* below): `odata_select` always, plus `odata_filter`,
  `odata_search`, `odata_top`, `odata_skip`, and `odata_skiptoken` when the set defines the hook
  that serves each. Calling it runs the same execution as `GET /<Set>` and returns the collection
  JSON.
- **`get_<Set>`** — registered for every set that implements `individual`. Its input schema is the
  entity key property (`required`) plus an optional `odata_select`. Calling it returns the
  individual JSON (same shape as `GET /<Set>('1')`). A not-found or uncoercible key is returned as
  a tool-error result (`isError: true`).
- **`count_<Set>`** — registered for every set that implements `count`. Its input schema is
  all-optional (`required: []`) and carries `odata_filter` and `odata_search` under the same gates
  as `list_<Set>`; both narrow the count (as they do for the OData `/$count` endpoint), and it
  returns the count as text (e.g. `"42"`). A set with neither hook takes no arguments at all.
- **`create_<Set>`** — registered for every writable set (one that implements
  [`create`](using_create_update_and_delete.md)). Its input schema is built from the entity type's
  properties; non-nullable properties become `required`.
- **`update_<Set>` / `delete_<Set>`** — registered for sets that implement `update` / `delete` — see
  [`using_create_update_and_delete.md`](using_create_update_and_delete.md).

`tools/list` returns these with their derived names, descriptions, and input schemas. A successful
`tools/call` returns the result inside a text content block (`result.content[0].text`) — the
collection/individual JSON for `list_`/`get_`, the numeric count as text for `count_`.

If an entity set declares a `description:`, it is appended to **every** tool's generated
description for that set, joined with `". "` (e.g. `"List People records. Attendees checked in at
the front desk"`), and each property's `description:` reaches `inputSchema.properties.<name>` on
every tool that exposes that property. See
[`doc/using_descriptions.md`](using_descriptions.md) for the full picture across `$metadata`,
`$oas2`, and MCP.

### Query options on the read tools

The six `odata_*` keys (`odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip`/
`odata_skiptoken`) exist because `$`-prefixed OData query option names are not valid Anthropic
tool-schema property keys. Each is translated back to its `$`-prefixed OData spelling before
reaching `Executor`, so calling `list_People` with `{"odata_filter": "name eq 'Alice'"}` runs the
exact same round trip as `GET /People?$filter=name eq 'Alice'`. `odata_skiptoken` is a coined name
following the same convention — OData itself spells it `$skiptoken`. Every other argument (record
keys, create/update property values) passes through unchanged.

Each key is advertised only when the entity set (class DSL) or resolver (builder DSL) defines the
hook that serves it, so an agent is never offered an option that could only answer with
`NoImplementationError`:

| Argument | OData | Advertised when the set/resolver defines |
| --- | --- | --- |
| `odata_filter` | `$filter` | any public `od_filter_*` hook — [`using_filter.md`](using_filter.md) |
| `odata_select` | `$select` | *always* — `$select` needs no hook, [`od_select`](using_select.md) is only an optimisation callback |
| `odata_search` | `$search` | `od_search` — [`using_search.md`](using_search.md) |
| `odata_top` | `$top` | `od_top` — [`using_paging.md`](using_paging.md) |
| `odata_skip` | `$skip` | `od_skip` — [`using_paging.md`](using_paging.md) |
| `odata_skiptoken` | `$skiptoken` | `od_skiptoken` — [`using_paging.md`](using_paging.md) |

`odata_filter` is gated on *any* public `od_filter_*` hook, including
[`od_filter_or`](using_filter.md) on its own, so its presence means "this set filters", not "every
property and operator works". The generated description says exactly that, and an unsupported
property/operator combination still comes back as a `NoImplementationError` tool-error result —
that remains how an agent discovers per-property limits.

`odata_select` is an **array** of property names rather than OData's comma-separated string, so its
`enum` can name exactly which properties are selectable; the array is joined back to `$select`'s
comma-separated spelling before execution. `odata_top`/`odata_skip` carry `"minimum": 0`. Every
read-tool query option carries a generated description.

A `People` set implementing `od_filter_eq`, `od_search`, `od_top`, `od_skip`, and `od_skiptoken`
advertises all six:

```jsonc
// tools/list result for the People set
{
  "name": "list_People",
  "description": "List People records",
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "odata_filter": { "type": "string", "description": "OData $filter expression; see the service instructions for the grammar. Filtering is supported for this entity set, but not every property or operator combination is necessarily implemented — an unsupported combination returns an error rather than an empty result. Property names are listed under odata_select. Example: user_name eq 'Alice'" },
      "odata_select": { "type": "array", "description": "Properties to return; omit for all.", "items": { "type": "string", "enum": ["id", "user_name", "emails"] } },
      "odata_search": { "type": "string", "description": "Free-text $search expression; terms combined with AND, OR, NOT. Parenthesised groups are not supported." },
      "odata_top":  { "type": "integer", "minimum": 0, "description": "Maximum number of records to return." },
      "odata_skip": { "type": "integer", "minimum": 0, "description": "Number of records to skip before returning results." },
      "odata_skiptoken": { "type": "string", "description": "Continuation token for the next page. Take it from the $skiptoken query parameter of a prior response's @odata.nextLink." }
    },
    "required": []
  }
}
```

A `Products` set that implements only `collection` advertises `odata_select` alone:

```jsonc
{
  "name": "list_Products",
  "description": "List Products records",
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "odata_select": { "type": "array", "description": "Properties to return; omit for all.", "items": { "type": "string", "enum": ["id", "name"] } }
    },
    "required": []
  }
}
```

`count_People` carries `odata_filter` and `odata_search` with the same texts. `get_People` takes
the same array-shaped `odata_select` alongside its `required` key property. The
`create_`/`update_`/`delete_` input schemas carry no `odata_*` keys at all.

Round trips, with `odata_select` joined back to the OData spelling:

```
list_People  {"odata_select": ["id", "user_name"], "odata_top": 2}
  -> GET /People?$select=id,user_name&$top=2
list_People  {"odata_skiptoken": "5"}
  -> GET /People?$skiptoken=5
count_People {"odata_filter": "user_name eq 'Alice'"}
  -> GET /People/$count?$filter=user_name eq 'Alice'   -> "1"
```

REST execution is unchanged by any of this: leaving an argument off a tool schema does not stop
`schema.execute` from honoring — or rejecting — the corresponding query option.

### Server `instructions`

The `initialize` result **always** carries an `instructions` string. It is the schema's own
`description:` (when it has one), a blank line, then a generated description of the OData dialect
the tools actually speak, composed in this order:

1. A fixed intro naming the `odata_*` aliasing.
2. The `$filter` grammar paragraph — only when at least one set in the schema supports filtering.
3. The `$search` line — only when at least one set defines `od_search`.
4. The `Paging:` line — only when at least one set defines `od_skiptoken`.
5. An unconditional line naming `$orderby`, `$expand`, `$apply`, `$compute` and `$count=true` as
   unsupported.
6. A closing line noting that each tool advertises only the options its own set supports.

For a schema described as `'Attendee records for the spring conference.'` containing the fully
capable `People` set above:

```json
{"jsonrpc":"2.0","id":1,"result":{
  "protocolVersion":"2025-06-18",
  "capabilities":{"tools":{}},
  "serverInfo":{"name":"Test OData API","version":"1.0.0"},
  "instructions":"Attendee records for the spring conference.\n\nThis service exposes a subset of OData v4. Query options are passed to tools as `odata_*` arguments (e.g. `odata_filter` is OData `$filter`).\n\n$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ne, gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with `or` is not supported, nor is parenthesised grouping. Functions (contains, startswith, tolower, …), arithmetic and `not` are not supported. String literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO 8601 (2024-01-31, 2024-01-31T00:00:00+00:00).\n$search: terms combined with AND, OR, NOT. Parenthesised groups are not supported.\nPaging: pass odata_skiptoken with the $skiptoken value from a prior response's @odata.nextLink.\n$orderby, $expand, $apply, $compute and $count=true are not supported.\n\nEach tool advertises only the query options its entity set supports."}}
```

A schema with no `description:` returns the dialect text alone — this is a change from previous
releases, where `instructions` was exactly `schema.description` and the key was omitted when there
was none. Nothing here is declared: the dialect text is generated from the same hook inference that
gates the tool arguments, so you write no documentation for it. See
[`doc/using_descriptions.md`](using_descriptions.md) for how `description:` composes with it.

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
  "serverInfo":{"name":"Test OData API","version":"1.0.0"},
  "instructions":"…"}}
```

(`instructions` is elided here for brevity — see *Server `instructions`* above for its content.)

## Common Error Cases

The server returns spec-compliant JSON-RPC error objects instead of crashing the transport with an
HTTP 500:

- **Unknown method** → JSON-RPC `-32601` (method not found).
- **Unknown tool, or a `create_`/`update_`/`delete_` on a set lacking that capability** →
  JSON-RPC `-32602` (invalid params) — such tools are simply not registered.
- **`resources/list`, `resources/templates/list`, or `resources/read`** → rejected with a JSON-RPC
  error: the server is tools-only and no longer advertises the `resources` capability.
- **An argument the input schema rejects** → the MCP SDK validates `tools/call` arguments against
  the tool's input schema *before* the handler runs, and returns a tool-error result
  (`isError: true`) carrying `"Invalid arguments: …"`. This covers `odata_select` given a string
  instead of an array, `odata_select` naming a property outside its `enum`, and a negative
  `odata_top`/`odata_skip` (rejected on `"minimum": 0`). Consequently `UnknownPropertyError` is not
  reachable through the MCP `$select` at all — it remains reachable through the REST `$select`, and
  through `odata_filter` naming a property the entity type doesn't have. A missing required
  argument (a `get_`/`update_`/`delete_` key) is reported as `"Missing required arguments: …"`.
- **A gated query option** → cannot produce `NoImplementationError` through MCP, because the
  argument does not exist to be passed. `NoImplementationError` remains reachable over REST for
  `$top`/`$skip`/`$skiptoken`/`$search`/`$filter`, and through MCP for `odata_filter` naming a
  property/operator with no matching hook (`"user_name eq not supported"`) or an `or` expression on
  a set without `od_filter_or` (`"OR filtering not supported"`).
- **OData-level errors during a `list_`/`get_`/`count_`/`create_`/... tool call** (e.g. a `$search`
  parse error, an `InvalidQueryOptionError`, or a `ResourceNotFoundError` for a missing `get_` key)
  → returned as a tool-error result (`isError: true`) whose content carries the error message,
  rather than crashing the transport.
- **`OdataDuty::InvalidMcpIdentifierError`** → raised by `to_mcp_server` itself (before a server
  is returned), when the Anthropic Messages API's identifier constraints would be violated:
  either an entity property name reaching a tool's input schema is over 64 characters or
  outside its allowed character set (e.g. non-ASCII), or an entity-set name pushes a generated
  tool name (e.g. `list_<Set>`) over 64 characters or outside its allowed character set. For
  example, a `PersonType` with a
  `日本語` property raises:

  ```
  OdataDuty::InvalidMcpIdentifierError:
  PersonType property "日本語" cannot be used as an MCP tool input key —
  it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)
  ```
