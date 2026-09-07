# Truthful MCP and `$oas2` query-option advertising

## Summary

Make the MCP tool surface and `$oas2` document advertise only the OData query options an entity set
can actually serve, describe the dialect's real grammar in the MCP server `instructions`, and
tighten the tool input schemas so unusable arguments are rejected before they reach the service. For
gem consumers whose OData service is driven by an AI agent over MCP.

## Goal / Problem

`list_<Set>` currently advertises `odata_filter`, `odata_top` and `odata_skip` unconditionally, but
each hard-fails with `NoImplementationError` when the corresponding hook is absent. Only
`odata_search` is gated on support today. An agent is therefore invited to filter a set that cannot
filter, and discovers otherwise only by failing.

The dialect is also never described. Nothing tells the model that this is a *subset* of OData v4 —
`eq ne gt ge lt le` only, all-`and` or all-`or` but never mixed, no parenthesised grouping, no
`contains()`/`startswith()`, no `$orderby`/`$expand`/`$apply`. A model with OData in its weights
emits `$filter=contains(name,'ali') and (a or b)` and eats an error.

Third, server-driven paging is a dead end: `od_skiptoken` and `@odata.nextLink` work over REST and
are advertised in `$oas2`, but MCP exposes no `odata_skiptoken` argument, so an agent receives a
`@odata.nextLink` it cannot act on.

`$oas2` already solves the first problem for `$top`/`$skip`/`$skiptoken`/`$search`/`$count` through
its per-parameter hook requirements; MCP is simply behind that precedent, and neither surface gates
`$filter`.

**Current behavior:** `list_Products` on a set implementing only `collection` advertises
`odata_filter`, `odata_select`, `odata_top`, `odata_skip`; three of the four raise
`NoImplementationError` on use. **Expected behavior:** it advertises `odata_select` alone.

## What it enables

- As a gem consumer, an agent calling my MCP server sees only the query options my entity set
  implements, so it stops proposing operations that are guaranteed to fail.
- As a gem consumer, my agent learns the supported `$filter` grammar and the explicitly unsupported
  OData features from the server `instructions`, without me writing any documentation.
- As a gem consumer, an agent can page through a large collection over MCP by feeding a
  `@odata.nextLink` token back as `odata_skiptoken`.
- As a gem consumer, an agent cannot name a property that doesn't exist in `$select`, because the
  valid names are an enum in the tool's input schema.
- As a gem consumer, my Swagger/`$oas2` document stops offering a `$filter` parameter on sets that
  cannot filter.

Scope limit: this pass does not make filterability *per-property* precise. A set is filterable or it
isn't; the description says so honestly and warns that individual property/operator combinations may
still be unimplemented.

## External API

No new DSL declaration is introduced. Capability continues to be inferred from the hooks a consumer
already writes, on both DSLs.

### Class-based DSL

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonType

  def od_after_init = @records = Person.all
  def collection = @records
  def individual(id) = @records.find { |r| r.id == id }
  def count = @records.size

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def od_search(expr) = @records = @records.select { |r| expr.terms.any? { |t| r.user_name.include?(t) } }
  def od_top(n)  = @records = @records.first(n)
  def od_skip(n) = @records = @records.drop(n)
  def od_skiptoken(token) = @records = @records.drop_while { |r| r.id <= token.to_i }
end

class ProductsSet < OdataDuty::EntitySet
  entity_type ProductType

  def od_after_init = @records = Product.all
  def collection = @records          # no filter / top / skip / search hooks
end
```

`PeopleSet` advertises the full read query-option set; `ProductsSet` advertises `odata_select` only.

### Builder DSL

Identical inference, applied to the `OdataDuty::SetResolver` subclass named by `resolver:`:

```ruby
class ProductsResolver < OdataDuty::SetResolver
  def od_after_init = @records = Product.all
  def collection = @records
end

schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                        scheme: 'http', base_path: '/api') do |s|
  s.title = 'Test OData API'
  s.version = '1.0.0'
  s.description = 'Attendee records for the spring conference.'
  product = s.add_entity_type(name: 'Product') do |et|
    et.property_ref 'id', Integer
    et.property 'name', String, nullable: false
  end
  s.add_entity_set(url: 'Products', entity_type: product, resolver: 'ProductsResolver')
end
```

### Capability rules

An entity set is **filterable** when its entity-set / resolver class defines any public instance
method whose name begins with `od_filter_`. This deliberately counts `od_filter_or` on its own: such
a set serves `a eq 1 or b eq 2` even though a single predicate fails, so some filtering genuinely
works.

The `od_filter_` prefix scan has no false positives from inheritance: neither `OdataDuty::EntitySet`
nor `OdataDuty::SetResolver` defines any method matching that prefix (the only `od_*` method either
base class provides is `od_next_link_skiptoken`), and the check excludes private methods, so nothing
is counted that a consumer did not write as a public hook.

The other gates reuse the existing per-hook rules: `od_top` for `$top`, `od_skip` for `$skip`,
`od_skiptoken` for `$skiptoken`, `od_search` for `$search`. `$select` remains **ungated** — it needs
no hook, since the projection happens regardless and `od_select` is only an optimisation callback.

### New argument name

`odata_skiptoken` is a **coined** name, not an OData term — but it follows the existing,
already-documented convention exactly: `$`-prefixed query-option names are illegal in Anthropic
tool-schema property keys, so each is aliased as `odata_<option>`. It joins the established set
`odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip` and is translated back to
OData `$skiptoken` before execution. Every other name in this document is the standard OData v4
spelling.

## Behavior & expected I/O

### `tools/list` — a set with no query-option hooks

Before:

```json
{"name": "list_Products", "description": "List Products records",
 "inputSchema": {"type": "object", "required": [], "properties": {
   "odata_filter": {"type": "string", "description": "OData $filter expression"},
   "odata_select": {"type": "string", "description": "Comma-separated properties to return"},
   "odata_top":    {"type": "integer", "description": "Max records to return"},
   "odata_skip":   {"type": "integer", "description": "Records to skip"}}}}
```

After:

```json
{"name": "list_Products", "description": "List Products records",
 "inputSchema": {"type": "object", "required": [], "properties": {
   "odata_select": {"type": "array", "description": "Properties to return; omit for all.",
                    "items": {"type": "string", "enum": ["id", "name"]}}}}}
```

### `tools/list` — a fully capable set

```json
{"name": "list_People", "description": "List People records",
 "inputSchema": {"type": "object", "required": [], "properties": {
   "odata_filter": {"type": "string", "description":
     "OData $filter expression; see the service instructions for the grammar. Filtering is supported for this entity set, but not every property or operator combination is necessarily implemented — an unsupported combination returns an error rather than an empty result. Property names are listed under odata_select. Example: user_name eq 'Alice'"},
   "odata_select": {"type": "array", "description": "Properties to return; omit for all.",
                    "items": {"type": "string", "enum": ["id", "user_name", "emails"]}},
   "odata_search": {"type": "string", "description":
     "Free-text $search expression; terms combined with AND, OR, NOT. Parenthesised groups are not supported."},
   "odata_top":  {"type": "integer", "minimum": 0,
                  "description": "Maximum number of records to return."},
   "odata_skip": {"type": "integer", "minimum": 0,
                  "description": "Number of records to skip before returning results."},
   "odata_skiptoken": {"type": "string", "description":
     "Continuation token for the next page. Take it from the $skiptoken query parameter of a prior response's @odata.nextLink."}}}}
```

`count_People` gains descriptions where it had none, and its `odata_filter` is gated by the same
rule:

```json
{"name": "count_People", "description": "Count People records",
 "inputSchema": {"type": "object", "required": [], "properties": {
   "odata_filter": {"type": "string", "description": "…same text as list_People…"},
   "odata_search": {"type": "string", "description": "…same text as list_People…"}}}}
```

`get_People`'s `odata_select` takes the same enum'd-array shape; its key property and `required` are
unchanged. `create_`/`update_`/`delete_` tools are untouched.

Property `description:` values continue to reach `inputSchema.properties.<name>.description`, and an
entity set's `description:` continues to be appended to every tool description for that set.
`$select`'s enum carries names only, not per-property descriptions.

### `initialize` — server `instructions`

The schema `description:` comes first, then a generated dialect section. Sections appear only when at
least one entity set in the schema supports the capability.

```json
{"jsonrpc": "2.0", "id": 1, "result": {
  "protocolVersion": "2025-06-18",
  "capabilities": {"tools": {}},
  "serverInfo": {"name": "Test OData API", "version": "1.0.0"},
  "instructions": "Attendee records for the spring conference.\n\nThis service exposes a subset of OData v4. Query options are passed to tools as `odata_*` arguments (e.g. `odata_filter` is OData `$filter`).\n\n$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ne, gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with `or` is not supported, nor is parenthesised grouping. Functions (contains, startswith, tolower, …), arithmetic and `not` are not supported. String literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO 8601 (2024-01-31, 2024-01-31T00:00:00+00:00).\n$search: terms combined with AND, OR, NOT. Parenthesised groups are not supported.\nPaging: pass odata_skiptoken with the $skiptoken value from a prior response's @odata.nextLink.\n$orderby, $expand, $apply, $compute and $count=true are not supported.\n\nEach tool advertises only the query options its entity set supports."}}
```

For a schema whose sets implement no `od_search`, the `$search` line is absent; with no filterable
set, the `$filter` paragraph is absent; with no `od_skiptoken`, the paging line is absent.

**Behavior change:** `instructions` was previously exactly `schema.description`, and the key was
omitted when that was `nil`. It is now always present — a schema with no `description:` returns the
dialect text alone.

### `tools/call` round trips

`odata_select` is joined to the OData comma-separated spelling; every other argument is translated as
today.

```
list_People {"odata_select": ["id", "user_name"], "odata_top": 2}
  -> GET /People?$select=id,user_name&$top=2

list_People {"odata_skiptoken": "5"}
  -> GET /People?$skiptoken=5

count_People {"odata_filter": "user_name eq 'Alice'"}
  -> GET /People/$count?$filter=user_name eq 'Alice'   -> "1"
```

### `$oas2`

`GET /Products` loses its `$filter` parameter (the set has no `od_filter_*` hook), alongside the
`$top`/`$skip`/`$skiptoken`/`$search`/`$count` gating that already applied. On sets that keep them,
`$top` and `$skip` gain `"minimum": 0` and `$select` gains an `items.enum` of the entity type's
property names:

```json
{"name": "$select", "in": "query", "type": "array", "collectionFormat": "csv",
 "items": {"type": "string", "enum": ["id", "user_name", "emails"]},
 "description": "Comma-separated list of properties to return"},
{"name": "$top", "in": "query", "type": "integer", "minimum": 0,
 "description": "Number of results to return"}
```

REST execution is unchanged throughout: hiding a parameter from `$oas2` does not stop the service
from honoring or rejecting it.

## Common error cases

Arguments are validated by the MCP SDK against the tool input schema *before* the handler runs, and a
failure is returned as a tool-error result (`isError: true`) carrying `"Invalid arguments: …"`:

- **`odata_select` given a string** (e.g. `"id,user_name"` instead of `["id","user_name"]`) →
  rejected by the SDK. The argument is strictly an array.
- **`odata_select` naming an unknown property** → rejected by the SDK on the `enum`.
  `UnknownPropertyError` is consequently no longer reachable through MCP `$select`; it remains
  reachable through the REST `$select` and through `odata_filter` naming a non-existent property.
- **`odata_top` / `odata_skip` given a negative integer** → rejected by the SDK on `minimum: 0`,
  rather than reaching `InvalidQueryOptionError` as it does over REST.
- **A missing required argument** (a `get_`/`update_`/`delete_` key) →
  `"Missing required arguments: …"`, unchanged.

Errors raised during execution continue to surface as tool-error results with the message text:

- **`NoImplementationError`** — `odata_filter` naming a property/operator with no matching hook
  (`"user_name eq not supported"`), or an `or` expression on a set without `od_filter_or`
  (`"OR filtering not supported"`). Still reachable, and the expected way an agent discovers
  per-property limits.
- **`UnknownPropertyError`** — `odata_filter` referencing a property that is not on the entity type.
- **`InvalidQueryOptionError`** — filtering a collection-valued property, or a malformed `$search`
  expression.
- **`ResourceNotFoundError`** — `get_`/`update_`/`delete_` with an unknown key.
- **`InvalidMcpIdentifierError`** — raised by `to_mcp_server` before a server is returned, unchanged.

`NoImplementationError` for `$top`/`$skip`/`$skiptoken`/`$search`/`$filter` becomes unreachable
*through MCP* for the gated cases, because the argument no longer exists to be passed. It remains
reachable over REST.

## Scope

**In:** MCP `list_`/`count_`/`get_` input schemas (capability gating, generated descriptions,
`minimum: 0`, `$select` enum, new `odata_skiptoken`); the MCP server `instructions`; `$oas2`
collection parameters (`$filter` gating, `$top`/`$skip` bounds, `$select` enum). Both the
class-based DSL and the builder DSL.

**Out:**

- `$metadata` is untouched — no change to `Capabilities.FilterRestrictions`, `SearchRestrictions`, or
  any other annotation. A set with no filter hooks still emits no `Filterable: false`.
- Per-property filterability: no enumeration of which properties accept which operators, in any
  surface.
- Structured/typed `$filter` arguments; the value stays a free-text OData expression.
- `$orderby`, `$expand`, `$apply` support — named as unsupported in `instructions`, not implemented.
- MCP resources (the server stays tools-only), tool `annotations` (`readOnlyHint` etc.), and
  `outputSchema`.
- Rewriting error messages to teach the supported surface.
- `create_`/`update_`/`delete_` tool input schemas.

## Documentation impact

Extend, in the existing style:

- **`doc/using_mcp.md`** — rewrite the `list_`/`count_`/`get_` bullets for the gated parameter sets,
  the new `odata_skiptoken`, the array-shaped `odata_select`, and the generated `instructions`.
- **`doc/using_descriptions.md`** — `instructions` is no longer just the schema `description:`;
  record the composition order and that the key is now always present.
- **`doc/using_paging.md`** — server-driven paging is now reachable from MCP.
- **`doc/using_oas2.md`** — `$filter` is now capability-gated; `$top`/`$skip` bounds and the
  `$select` enum.
- **`doc/using_filter.md`** — note that filter capability is inferred from any `od_filter_*` hook and
  drives what MCP and `$oas2` advertise.
- **`AGENTS.md`** (`CLAUDE.md` is its symlink) — update the `$filter`, `$select`, Paging and MCP
  entries in the Features index so they still match the guides above.

`README.md` needs no change: it carries no MCP or query-option examples.
