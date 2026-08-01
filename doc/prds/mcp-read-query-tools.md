# PRD: MCP read/query tools — agents manage data through the API

## Summary

Expose an OData entity set's **read** operations (get-by-id, list, count) as model-invokable
**MCP tools**, alongside the existing `search`/`create`/`update`/`delete` tools, and **replace** the
current MCP read *resources* with those tools. This gives an AI agent a complete, model-controlled
read→act loop over a schema without depending on client-side resource support.

## Goal / Problem

Today the MCP surface is split:

- **Tools (model-controlled):** `search_<Set>` (only when `od_search` is defined), `create_<Set>`,
  `update_<Set>`, `delete_<Set>`.
- **Resources (application/user-controlled):** `<url>('{id}')` individual template,
  `<url>?$top={top}&$skip={skip}` collection template, `<url>/$count`.

Per the MCP spec, tools are *model-controlled* (the agent decides when to call them) while resources
are *application-controlled* (the host app or user decides when to load them). Most agent clients
today do **not** autonomously read MCP resources — they surface them for manual selection. So an
autonomous agent can create/update/delete but **cannot reliably read**: it can't fetch a record by
key or browse a collection on its own, and `update`/`delete` both need a key the agent has no
tool-based way to discover (unless `od_search` happens to be defined).

- **Current behavior:** reads are resource-only → agents can't autonomously read.
- **Expected behavior:** reads are tools → agents can list, get, and count records themselves, then
  act on the results.

## What it enables

- As a gem consumer, when I define `collection`, my set advertises a **`list_<Set>`** tool that an
  agent can call with `$filter`/`$select`/`$search`/`$top`/`$skip` to browse and narrow records.
- As a gem consumer, when I define `individual`, my set advertises a **`get_<Set>`** tool that an
  agent can call with a key to read one record (optionally projecting with `$select`).
- As a gem consumer, when my set supports `count`, it advertises a **`count_<Set>`** tool returning
  the count (optionally narrowed by `$filter`/`$search`).
- As an agent, I can complete a full loop — `list_People` → pick an `id` →
  `update_People`/`delete_People` — entirely through tools, with no dependence on client resource
  support.

**Scope limit:** this changes only the MCP surface. REST/OData GET, `$metadata`, index, and `$oas2`
outputs are unchanged. Reads remain gated on the same hooks that gate them today (`collection`,
`individual`, `count`).

## External API

This introduces **no new consumer DSL** — the tools are inferred from the same `od_*` hooks that
already power reads, exactly as `create`/`update`/`delete` tools are inferred from those methods. A
consumer who already writes `collection`, `individual`, and (implicitly) `count` gets the new tools
automatically.

### Class-based DSL (unchanged consumer code; new tools inferred)

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init      = (@records = Person.all)
  def collection         = @records                       # ⇒ list_People tool + count_People tool
  def individual(id)     = @records.find { _1.id == id }  # ⇒ get_People tool
  def od_search(expr)    = ExpressionMatcher.new(expr).filter(@records) # ⇒ $search + search_People
end
```

### Builder DSL (unchanged; resolver drives the same inference)

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init  = (@records = Person.all)
  def collection     = @records                        # ⇒ list_People + count_People
  def individual(id) = @records.find { _1.id == id }   # ⇒ get_People
end
```

### Inference contract (observable)

- A set that implements `collection` advertises `list_<Set>` and `count_<Set>`.
- A set that implements `individual` advertises `get_<Set>`.
- `$search` appears in `list_<Set>`/`count_<Set>` input schemas, and `search_<Set>` is advertised,
  only when `od_search` is defined (unchanged gating).
- A set that implements none of the read hooks advertises none of these tools.

## Behavior & expected I/O

### New tools in `tools/list`

```jsonc
// list_<Set> — collection browse (od_search defined ⇒ $search present)
{
  "name": "list_People",
  "description": "List People records",
  "inputSchema": {
    "type": "object",
    "properties": {
      "$filter": { "type": "string", "description": "OData $filter expression" },
      "$select": { "type": "string", "description": "Comma-separated properties to return" },
      "$search": { "type": "string", "description": "Search expression (AND, OR, NOT)" },
      "$top":    { "type": "integer", "description": "Max records to return" },
      "$skip":   { "type": "integer", "description": "Records to skip" }
    },
    "required": []
  }
}
```

```jsonc
// get_<Set> — read one by key (key property + optional $select)
{
  "name": "get_People",
  "description": "Get a single People record by ID",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id":      { "type": "string", "readOnly": true },
      "$select": { "type": "string", "description": "Comma-separated properties to return" }
    },
    "required": ["id"]
  }
}
```

```jsonc
// count_<Set> — count (optionally narrowed; $search only when od_search defined)
{
  "name": "count_People",
  "description": "Count People records",
  "inputSchema": {
    "type": "object",
    "properties": {
      "$filter": { "type": "string" },
      "$search": { "type": "string" }
    },
    "required": []
  }
}
```

### `tools/call` results

- `list_People` → the collection JSON (same shape as `GET /People`), inside `result.content[0].text`.
- `get_People` `{ "id": "1" }` → the individual JSON (same shape as `GET /People('1')`).
- `count_People` → the count as text (e.g. `"42"`).

Each reuses the same OData execution path as the equivalent REST GET; query options are forwarded
verbatim.

### Removed resources (the "convert")

- `resources/list` → **empty** (the `<url>/$count` resource is gone; `count_<Set>` tool replaces it).
- `resources/templates/list` → **empty** (individual + paginated-collection templates are gone;
  `get_<Set>`/`list_<Set>` replace them).
- `resources/read` → no longer serves data (no resources are advertised).
- Server `capabilities` narrows from `{ tools: {}, resources: {} }` to `{ tools: {} }`.

### Before / after (searchable, writable People set)

| | Before | After |
|---|---|---|
| `tools/list` | `search_People`, `create_People`, `update_People`, `delete_People` | `search_People`, **`list_People`**, **`get_People`**, **`count_People`**, `create_People`, `update_People`, `delete_People` |
| `resources/templates/list` | `People('{id}')`, `People?$top=…&$skip=…` | *(empty)* |
| `resources/list` | `People/$count` | *(empty)* |
| capabilities | `tools`, `resources` | `tools` |

## Common error cases

- **`get_<Set>` with a key that doesn't exist** → `ResourceNotFoundError` (`No such entity <id>`),
  surfaced as a tool-error result (`isError: true`), same as `GET /People('<id>')`.
- **`get_<Set>` with an uncoercible key** → `InvalidPropertyReferenceValue`
  (`Invalid individual id : …`), as a tool-error result.
- **`list_<Set>`/`count_<Set>` with a malformed `$filter`/`$search` or unknown query option** →
  `InvalidQueryOptionError` / `$search` parse error, as a tool-error result — never crashes the
  transport (consistent with today's `search_<Set>`).
- **`$select` naming an undefined property** → `UnknownPropertyError`, as a tool-error result.
- **`$search` supplied to a set without `od_search`** → the property is not advertised; if sent
  anyway it is rejected as an invalid query option, as a tool-error result.
- **Calling `list_/get_/count_<Set>` for a set lacking the corresponding read hook** → the tool is
  never registered, so `tools/call` raises `Unknown tool: <tool>` (mirrors
  `create_`/`update_`/`delete_`).

## Scope

- **In:** MCP `tools/list` + `tools/call` gain `list_<Set>`, `get_<Set>`, `count_<Set>`; MCP read
  resources/templates and the `resources` capability are removed. Both DSLs (class-based and builder).
- **Out:** No change to REST/OData GET, `$metadata`, index JSON, or `$oas2`. No new consumer DSL
  keyword or hook. No new query options beyond the existing OData ones. Prompts and sampling
  primitives are untouched.
- **Breaking change:** resource-aware MCP clients relying on the individual/collection/count
  resources must switch to the equivalent tools.

## Documentation impact

Update **`doc/using_mcp.md`** — rewrite the "Resources and resource templates" section to document
`list_<Set>`/`get_<Set>`/`count_<Set>` under "Tools" and state that read resources have been removed
(tools-only server). Add a short cross-reference from **`doc/using_create_update_and_delete.md`** so
the read→act loop is discoverable. Refresh the MCP tool/resource description in `CLAUDE.md`'s
Architecture and Features sections. No new guide file needed. (Write the guide changes only when the
implementation lands, not from this PRD.)

## Terminology check (OData mapping)

- `list_<Set>` → OData **collection GET**; tracks OAS2 `operationId: List<Set>`. Verb-prefixed MCP
  tool name follows the existing `create_/update_/delete_<Set>` convention (coined MCP name; there is
  no OData vocabulary annotation for "expose as tool").
- `get_<Set>` → OData **read entity by key** ("individual" GET); tracks OAS2
  `operationId: GetIndividual<Set>ById`.
- `count_<Set>` → OData **`/$count`** system query option.
- `$filter`, `$select`, `$search`, `$top`, `$skip` → OData **system query options**, exact spelling.
- Read availability corresponds conceptually to `Org.OData.Capabilities.V1.ReadRestrictions` /
  `ReadByKeyRestrictions`, but — as today — no "not readable" annotation is emitted; reads default to
  available.

## Open questions

- **`search_<Set>` vs. `list_<Set>`+`$search` overlap:** with `$search` now on `list_<Set>`,
  `search_<Set>` becomes partly redundant. Keep both (backward compatible) as drafted, or deprecate
  `search_<Set>` in favor of `list_<Set>`? Draft keeps both.
- **`count_<Set>` options:** draft exposes `$filter`/`$search` (the options that change a count) and
  intentionally omits `$top`/`$skip`/`$select`. Confirm that's the desired surface.
