# Using MCP with OdataDuty

OdataDuty turns the schema you already defined for OData into a [Model Context
Protocol](mcp_crash_course.md) (MCP) server, so AI agents can list, read, search, and write your
entities through the same data methods that power your REST endpoints. You define the schema once;
the tools are derived from it automatically.

Everything protocol-level — JSON-RPC plumbing, lifecycle, version negotiation, capability exchange,
argument validation, error objects — is handled by the official [`mcp` Ruby
SDK](https://ruby.sdk.modelcontextprotocol.io/). This guide covers the part that is OdataDuty's:
what your schema turns into, and which of your hooks decide it.

## Overview

- **Entry point:** `schema.to_mcp_server` returns a bare `MCP::Server`. Works for **both** the
  class-based DSL (`OdataDuty::Schema`) and the builder DSL (`OdataDuty::SchemaBuilder`).
- **Nothing to declare:** tool names, input schemas, and descriptions are all inferred from the
  data methods and `od_*` hooks you already write. There is no MCP-specific DSL.
- **Tools-only:** reads are exposed as model-invokable tools, not MCP resources.
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

`to_mcp_server` derives the whole tool surface from your schema — you do not register tools by
hand. A tool is registered only when the set implements the data method behind it, so an agent sees
exactly the operations your sets can perform.

### Tools

Reads are exposed as tools, so an agent can complete a full loop through tools alone: `list_<Set>`
to find records, then `get_/update_/delete_<Set>` by a discovered key.

| Tool | Registered when the set implements | Takes | Returns |
| --- | --- | --- | --- |
| `list_<Set>` | `collection` | the query options the set can serve, all optional | the collection, as `GET /<Set>` would |
| `get_<Set>` | `individual` | the entity key (required) + `odata_select` | the individual record |
| `count_<Set>` | `collection` **and** `count` | `odata_filter`/`odata_search` when supported | the count, as text |
| `create_<Set>` | [`create`](using_create_update_and_delete.md) | the entity type's writable properties; non-nullable ones required | the created record |
| `update_<Set>` | [`update`](using_create_update_and_delete.md) | the entity key + the properties you may change | the updated record |
| `delete_<Set>` | [`delete`](using_create_update_and_delete.md) | the entity key | a confirmation payload |

Every tool runs the same execution path as the equivalent REST request, so a tool call and a `GET`
answer identically. The payload arrives as a JSON string in a single text content block
(`result.content[0].text`) rather than as structured content. Errors raised while resolving a
call — a missing key, an unsupported filter, a malformed `$search` — come back in that same slot
as a tool error (`isError: true`) carrying the message, not as transport failures.

If an entity set declares a `description:`, it is appended to **every** tool's generated
description for that set (e.g. `"List People records. Attendees checked in at the front desk"`),
and each property's `description:` reaches that property in the tool's input schema. See
[`doc/using_descriptions.md`](using_descriptions.md) for the full picture across `$metadata`,
`$oas2`, and MCP.

### Query options on the read tools

The read tools accept OData query options under `odata_*` names, because `$`-prefixed names are not
valid tool-schema property keys. Each is translated back to its OData spelling before execution, so
calling `list_People` with `{"odata_filter": "name eq 'Alice'"}` runs the exact same round trip as
`GET /People?$filter=name eq 'Alice'`.

**Each option is advertised only when your set defines the hook that serves it**, so an agent is
never offered an option that could only answer with `NoImplementationError`:

| Argument | OData | Advertised when the set/resolver defines |
| --- | --- | --- |
| `odata_filter` | `$filter` | any public `od_filter_*` hook — [`using_filter.md`](using_filter.md) |
| `odata_select` | `$select` | *always*, on `list_`/`get_` — `$select` needs no hook, [`od_select`](using_select.md) is only an optimisation callback. `count_` never takes it |
| `odata_search` | `$search` | `od_search` — [`using_search.md`](using_search.md) |
| `odata_top` | `$top` | `od_top` — [`using_paging.md`](using_paging.md) |
| `odata_skip` | `$skip` | `od_skip` — [`using_paging.md`](using_paging.md) |
| `odata_skiptoken` | `$skiptoken` | `od_skiptoken` — [`using_paging.md`](using_paging.md) |

So a `People` set implementing `od_filter_eq`, `od_search`, `od_top`, `od_skip` and `od_skiptoken`
offers all six, while a `Products` set implementing only `collection` offers `odata_select` alone.
`create_`/`update_`/`delete_` tools carry no `odata_*` keys at all.

Three details shape how well an agent uses them:

- **`odata_select` is an array of property names**, not OData's comma-separated string, so the
  schema can name exactly which properties are selectable and the SDK rejects anything else. The
  array is joined back to `$select`'s comma-separated spelling before execution.
- **`odata_top`/`odata_skip` are bounded at zero**, so a negative page size is rejected before it
  reaches your hooks.
- **`odata_filter` means "this set filters", not "every property and operator works."** It is gated
  on *any* public `od_filter_*` hook, including [`od_filter_or`](using_filter.md) on its own. Its
  generated description says so, and an unsupported property/operator combination still comes back
  as a `NoImplementationError` tool error — that remains how an agent discovers per-property
  limits.

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

Clients negotiating protocol version `2025-03-26` or later receive an `instructions` string
describing the service (the SDK drops the key on `2024-11-05`). It is your schema's own
`description:` (when it has one), then a generated description of the OData dialect the tools
actually speak, composed in this order:

1. A fixed intro naming the `odata_*` aliasing.
2. The `$filter` grammar — the supported operators, that `and` and `or` cannot be mixed, that
   parenthesised grouping and functions like `contains()` are unsupported, and how literals are
   spelled. Included only when at least one set in the schema supports filtering.
3. The `$search` grammar — only when at least one set defines `od_search`.
4. How to page with `odata_skiptoken` — only when at least one set defines `od_skiptoken`.
5. An unconditional line naming `$orderby`, `$expand`, `$apply`, `$compute` and `$count=true` as
   unsupported.
6. A closing line noting that each tool advertises only the options its own set supports.

This is what stops a model from confidently emitting `contains(name,'ali') and (a or b)` — OData
that is perfectly valid in general, but not in this dialect. You write none of it: the text is
generated from the same hook inference that gates the tool arguments. The exact wording is pinned
by the `schema_mcp_instructions_spec.rb` specs in both spec trees.

A schema with no `description:` returns the dialect text alone. This is a change from previous
releases, where `instructions` was exactly `schema.description` and was omitted when there was
none. See [`doc/using_descriptions.md`](using_descriptions.md) for how `description:` composes
with it.

### No MCP resources (tools-only)

The server registers no MCP resources or resource templates, and advertises no `resources`
capability — so resource requests are rejected by the SDK. Reads that an MCP server might otherwise
expose as resources (individual-by-id, paginated collection, `/$count`) are served by the
`list_<Set>`, `get_<Set>`, and `count_<Set>` tools instead.

## Common Error Cases

Bad requests come back as protocol or tool errors rather than crashing the transport. The cases
worth knowing about as a gem consumer:

- **An argument the input schema rejects** — the SDK validates `tools/call` arguments *before* your
  handler runs and returns a tool error. This covers `odata_select` given a string instead of an
  array or naming a property outside its `enum`, and a negative `odata_top`/`odata_skip`. So
  `UnknownPropertyError` is not reachable through the MCP `$select` at all; it remains reachable
  through the REST `$select`, and through `odata_filter` naming a property the entity type doesn't
  have.
- **A query option your set doesn't support** — cannot raise `NoImplementationError` through MCP,
  because the argument was never advertised to be passed. It remains reachable over REST, and
  through `odata_filter` for a property/operator with no matching hook or an `or` expression on a
  set without `od_filter_or`.
- **A tool that doesn't exist** — including a `create_`/`update_`/`delete_` on a set lacking that
  capability, since such tools are simply never registered.
- **OData errors during a call** — a `$search` parse failure, an `InvalidQueryOptionError`, a
  `ResourceNotFoundError` for a missing `get_` key — are returned as tool errors carrying the
  message.
- **`OdataDuty::InvalidMcpIdentifierError`** — raised by `to_mcp_server` itself, before a server is
  returned, when a name in your schema cannot be a valid MCP identifier: a property name that
  reaches a tool's input schema, or an entity-set name that makes a generated tool name (e.g.
  `list_<Set>`) too long or non-conforming. This is a schema-definition bug, so it surfaces at
  build time rather than per request. For example, a `PersonType` with a `日本語` property raises:

  ```
  OdataDuty::InvalidMcpIdentifierError:
  PersonType property "日本語" cannot be used as an MCP tool input key —
  it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)
  ```
