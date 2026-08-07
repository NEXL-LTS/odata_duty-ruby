# Fix: MCP tool schemas must use Anthropic-safe identifiers

## Summary

`to_mcp_server` (both DSLs) currently generates MCP tool `input_schema.properties` keys —
and, latently, tool names — that can violate the Anthropic Messages API's identifier
constraints. This breaks every tool on the server for any Claude-based MCP client, since a
single invalid key rejects the whole `tools/list` payload. This PRD fixes the generator to
only ever emit Anthropic-safe identifiers, failing loudly at `to_mcp_server` build time
instead of failing opaquely at the API boundary.

## Goal / Problem

**Current behavior:** `to_mcp_server` emits query-option keys (`$filter`, `$select`,
`$search`, `$top`, `$skip`) verbatim as JSON Schema property names on `list_<Set>`,
`count_<Set>`, and `get_<Set>` tools. `$` is outside the pattern the Anthropic Messages API
enforces on tool `input_schema.properties` keys — `^[a-zA-Z0-9_.-]{1,64}$` — so every tool
carrying a query option is rejected the moment its schema reaches the API, with no partial
degradation: the entire toolset becomes uncallable.

The same class of failure is latent wherever a property name flows into a tool schema
verbatim: `create_<Set>`/`update_<Set>`/`get_<Set>`/`delete_<Set>` schemas use
`property.name` directly as a JSON Schema key, and OData property names may contain any
Unicode letter (`été`, `日本語`) and have no length limit — both valid under
`OdataDuty::Property::NAME_REGEXP`, both invalid under the Anthropic pattern. The same is
true of `list_<Set>`/`count_<Set>`/`get_<Set>`/`create_<Set>`/`update_<Set>`/`delete_<Set>`
tool *names*, which are built by concatenating a verb prefix onto the entity set's name and
are subject to Anthropic's equivalent tool-name pattern, `^[a-zA-Z0-9_-]{1,64}$` (the same
character class, without `.`).

**Expected behavior:** `to_mcp_server` never emits a tool name or an `input_schema`
property key that violates the consuming API's constraints. Where a rename can make an
identifier safe (the five query options), it does so consistently and reversibly. Where no
safe rename exists without changing what the identifier *means* to the consumer (an
entity's own property or entity-set name), `to_mcp_server` raises immediately, naming the
offending entity type/set and property, rather than shipping a broken schema that fails
later as an opaque `400` from the API.

## What it enables

- As a gem consumer, I can call `schema.to_mcp_server` and get a server whose `tools/list`
  response is guaranteed to pass Anthropic's tool-schema validation, without auditing
  property names myself.
- As a gem consumer building an MCP tool caller, I can pass `odata_filter`, `odata_select`,
  `odata_search`, `odata_top`, `odata_skip` to `list_<Set>` / `count_<Set>` / `get_<Set>`
  tools and get exactly the same result as the equivalent `$filter`/`$select`/`$search`/
  `$top`/`$skip` REST request.
- As a gem consumer with a non-ASCII or very long property/entity-set name, I get a clear,
  named `to_mcp_server`-time error instead of a working-looking server whose tools all fail
  at the API layer.
- Out of scope: automatically transliterating or truncating an invalid name into a safe one.
  A property or entity-set name is user-visible identity; silently renaming it for MCP would
  surprise the consumer more than a named error does.

## External API

### Renamed query-option keys (Half 1)

`list_<Set>`/`count_<Set>`/`get_<Set>` input schemas stop using the OData query-option
spelling as the JSON Schema key and use an `odata_`-prefixed alias instead. This is a single
shared mapping, used both when building the schema and when translating a tool call back
into OData query options — the two directions never drift independently:

| OData System Query Option ([OData-Protocol §11.2.5](../odata_crash_course.md)) | MCP input-schema key |
|---|---|
| `$filter` | `odata_filter` |
| `$select` | `odata_select` |
| `$search` | `odata_search` |
| `$top` | `odata_top` |
| `$skip` | `odata_skip` |

**Coined name.** OData has no ASCII-safe spelling for its `$`-prefixed system query
options — the `odata_` prefix is not an OData term or vocabulary annotation, it exists
purely so these keys satisfy the Anthropic Messages API's tool-identifier pattern. Nothing
else about the query options changes: they still narrow the same `list_<Set>`/`count_<Set>`
call the way `$filter`/`$select`/`$search`/`$top`/`$skip` narrow the equivalent
`GET /<Set>` / `GET /<Set>/$count` request.

Neither DSL changes how a consumer *declares* a set — `od_filter_eq/ne/gt/lt`, `od_search`,
paging, etc. are unaffected. The rename is entirely inside the generated MCP tool surface:

```ruby
# Class-based DSL — unchanged declaration
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonType
  def collection = @records
  def od_search(expression) = @records.select { |r| expression.match?(r.name) }
end

server = MySchema.to_mcp_server
# list_People's input_schema.properties now has odata_filter / odata_select /
# odata_search / odata_top / odata_skip instead of $filter / $select / $search / $top / $skip
```

```ruby
# Builder DSL — same result via SchemaBuilder
schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                        scheme: 'http', base_path: '/api') do |s|
  person = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', Integer }
  s.add_entity_set(url: 'People', entity_type: person, resolver: 'TestPersonResolver')
end
server = schema.to_mcp_server
```

Calling a tool with the new key names still reaches `Executor` as the original OData query
option — a `tools/call` for `list_People` with `{"odata_filter": "name eq 'Alice'"}`
produces the exact same result as `GET /People?$filter=name eq 'Alice'`.

### Build-time validation of every generated identifier (Half 3)

`to_mcp_server` validates every JSON Schema property key and every tool name it is about to
emit against the Anthropic-safe pattern, **after** the query-option rename above is applied.
This closes the two latent failure classes (non-ASCII / oversized property names; long
entity-set names producing an oversized tool name) instead of leaving them for the next bug
report:

- **Input-schema property keys** (the `odata_*` aliases, plus every entity property name
  used verbatim in `create_<Set>`/`update_<Set>`/`get_<Set>`/`delete_<Set>` schemas,
  including the entity's key property) must match `\A[a-zA-Z0-9_.-]{1,64}\z` — the exact
  pattern the Anthropic Messages API enforces on `input_schema.properties` keys.
- **Tool names** (`list_<Set>`, `count_<Set>`, `get_<Set>`, `create_<Set>`, `update_<Set>`,
  `delete_<Set>`) must match `\A[a-zA-Z0-9_-]{1,64}\z` — Anthropic's equivalent constraint
  on the tool `name` field itself (the same character class, without `.`).

A schema built from user-defined fields can violate either constraint even though every
name involved is perfectly valid OData: `OdataDuty::Property::NAME_REGEXP` allows any
Unicode letter and imposes no length limit, and this check does not change that — a `été`
or `日本語` property, or an entity-set name long enough to push `create_<Set>` past 64
characters, remains valid to declare. It only becomes a problem the moment
`to_mcp_server` tries to expose it, and that is where `to_mcp_server` now raises.

On violation, `to_mcp_server` raises `OdataDuty::InvalidMcpIdentifierError` (a new
`ArgumentError` subclass, alongside `InvalidNCNamesError`) naming the entity set, the tool
or property involved, and the value that failed. Validation walks endpoints in schema
declaration order and, within an endpoint, tools in the order `list`, `count`, `get`,
`create`, `update`, `delete`, raising on the first violation found — so the error is
deterministic and reproducible.

This applies identically to the class-based DSL and the builder DSL: both funnel through
the same `to_mcp_server` entry point and the same generated tool/schema surface, so nothing
DSL-specific is introduced.

## Behavior & expected I/O

### `tools/list` after the fix

```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
```

```json
{"jsonrpc":"2.0","id":1,"result":{"tools":[
  {
    "name": "list_People",
    "description": "List People records",
    "inputSchema": {
      "type": "object",
      "properties": {
        "odata_filter": {"type": "string", "description": "OData $filter expression"},
        "odata_select": {"type": "string", "description": "Comma-separated properties to return"},
        "odata_search": {"type": "string", "description": "Search expression (AND, OR, NOT)"},
        "odata_top": {"type": "integer", "description": "Max records to return"},
        "odata_skip": {"type": "integer", "description": "Records to skip"}
      },
      "required": []
    }
  }
]}}
```

Every key in every tool's `inputSchema.properties`, across all 24 tools in the reported
8-entity-set/24-tool schema, now matches `^[a-zA-Z0-9_.-]{1,64}$` — the repro script in the
original bug report runs clean.

### Round trip: a tool call still executes the OData query option

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call",
 "params":{"name":"list_People","arguments":{"odata_filter":"name eq 'Alice'","odata_top":1}}}
```

Executes exactly as `GET /People?$filter=name eq 'Alice'&$top=1` — same collection JSON
back in the tool's text content block. A `get_People` call's own record-key argument (e.g.
`{"id": "1", "odata_select": "name"}`) is unaffected: only the five reserved keys above are
translated back to their OData spelling before reaching `Executor`; every other argument
(record keys, create/update property values) passes through as today.

### Before / after: non-ASCII property name

```ruby
class PersonType < OdataDuty::EntityType
  property_ref :id, Integer
  property :日本語, String   # valid OData property name today
end
```

- **Before this fix:** `to_mcp_server` succeeds; `create_People`'s `input_schema` contains
  the raw `"日本語"` key; the Anthropic API rejects the whole toolset at `tools/list` time.
- **After this fix:** `to_mcp_server` raises immediately:

  ```
  OdataDuty::InvalidMcpIdentifierError:
  PersonType property "日本語" cannot be used as an MCP tool input key —
  it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)
  ```

### Before / after: entity-set name pushes a tool name over 64 characters

```ruby
class ThisIsAnExtremelyLongEntitySetNameThatPushesTheGeneratedToolNameOverTheLimitSet < OdataDuty::EntitySet
  entity_type PersonType
  def collection = @records
end
```

- **Before this fix:** `to_mcp_server` succeeds; `list_<that 74-character name>` is 79
  characters, rejected by the Anthropic API's tool-name pattern.
- **After this fix:**

  ```
  OdataDuty::InvalidMcpIdentifierError:
  tool name "list_ThisIsAnExtremelyLong...Set" is 79 characters — MCP tool names must
  match /\A[a-zA-Z0-9_-]{1,64}\z/
  ```

## Common Error Cases

- **`OdataDuty::InvalidMcpIdentifierError`** (new, `ArgumentError`) — raised by
  `to_mcp_server`, before the server object is returned, when a generated tool name or
  `input_schema` property key would violate the Anthropic-safe pattern. Covers: a non-ASCII
  or over-64-character entity property name reaching a `create_`/`update_`/`get_`/`delete_`
  schema; an entity-set name that pushes a generated tool name over 64 characters or outside
  its allowed character set; and the residual case where an entity property is literally
  named `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip` and collides
  with the reserved query-option key in a `list_`/`count_`/`get_` schema.
- **`NoImplementationError`, `UnknownPropertyError`, `InvalidQueryOptionError`,
  `ResourceNotFoundError`** — unchanged. These are raised during `tools/call` execution (via
  `Executor`), not by this fix; a tool call with a bad `odata_filter` expression still
  surfaces as a tool-error result exactly as `$filter` does today for REST.

## Scope

**In scope:**
- Renaming the five query-option MCP keys (`$filter`/`$select`/`$search`/`$top`/`$skip` →
  `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip`) via one shared
  mapping used for both schema generation and round-trip translation.
- Validating every generated `input_schema` property key and every generated tool name
  against the Anthropic-safe patterns at `to_mcp_server` time, raising
  `OdataDuty::InvalidMcpIdentifierError` on the first violation.
- Both DSLs — class-based (`OdataDuty::Schema`) and builder (`OdataDuty::SchemaBuilder`) —
  since both share the same `to_mcp_server` code path and tool/schema surface.

**Out of scope:**
- Changing `OdataDuty::Property::NAME_REGEXP` or any OData-side name validation. A `日本語`
  or 100-character property name remains perfectly valid for `$metadata`, `$oas2`, and REST
  — it only becomes an error when it would be exposed as an MCP identifier.
- Transliterating, truncating, or otherwise auto-sanitizing an invalid property or
  entity-set name into a safe one. This fix always fails loudly instead.
- Preserving the old `$filter`/`$select`/`$search`/`$top`/`$skip` MCP keys as a
  backwards-compatible alias. This is a breaking rename of the MCP tool surface; no
  Claude-based client could have been calling the old spelling successfully, since it never
  passed API validation, but other MCP clients that happened to tolerate the old keys are
  affected. Warrants a minor version bump (current: `0.30.1`) and a note in the gem's
  release notes.
- MCP resources, the `resources` capability, or anything else about the tools-only
  transport — unaffected by this fix.

## Documentation impact

Extend **`doc/using_mcp.md`**:
- Update the "Tools" section's per-tool key lists (`list_<Set>`, `count_<Set>`, `get_<Set>`)
  to show `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip` in place of
  the `$`-prefixed spellings, and note the round trip back to the OData query option.
- Add `OdataDuty::InvalidMcpIdentifierError` to "Common Error Cases", with the two triggering
  conditions (property name, tool name) and a short example.
