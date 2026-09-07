# Build plan — Truthful MCP and `$oas2` query-option advertising

PRD: [`truthful-query-option-advertising.md`](truthful-query-option-advertising.md)

Five ordered tasks. Each lands as one commit once `review-task` reports `REVIEW_OK`.

Standing constraints for every task: TDD per `doc/conventions/workflows/test-driven-development.md`;
public-API-only specs (`doc/conventions/specs.md`); two-space indent / 99-char lines / RuboCop
metrics (`MethodLength` 13, `Class`/`ModuleLength` 99, `AbcSize` 30, `CyclomaticComplexity` 7);
`bundle exec rake` green (RSpec + RuboCop + 100% line/branch coverage) as the definition of done.

Note on DSL symmetry: MCP is shared by both DSLs (`McpServerBuilder` walks `schema.endpoints`, which
is `EntitySet::Metadata` objects for the class DSL and `SchemaBuilder::Endpoint` objects for the
builder DSL), so tasks 1–3 touch both. `OAS2.build_json` accepts only a `SchemaBuilder::Schema`
(the class-based `OdataDuty::Schema` exposes no `host`/`scheme`/`collection_entity_sets`), so task 4
is builder-DSL only and says so.

---

## - [x] Task 1 — Capability-gate the MCP `list_`/`count_` query-option arguments, and add `odata_skiptoken`

**Task text:** Make the `list_<Set>` and `count_<Set>` MCP tool input schemas advertise only the
query options the entity set can actually serve, and add the new `odata_skiptoken` argument.

Add capability predicates, inferred from hook presence, to **both** DSLs:

- `supports_filter?` — true when the entity-set class (class DSL) or resolver class (builder DSL)
  defines **any public instance method whose name begins with `od_filter_`**. This deliberately
  counts `od_filter_or` on its own. Private methods must not count. Neither `OdataDuty::EntitySet`
  nor `OdataDuty::SetResolver` defines a method matching the prefix, so inheritance yields no false
  positives.
- `supports_top?` → `od_top`, `supports_skip?` → `od_skip`, `supports_skiptoken?` → `od_skiptoken`.

Place them alongside the existing `supports_search?` / `supports_filter_or?` / `supports_count?`
predicates in `OdataDuty::EntitySet::Metadata` (class DSL) and `SchemaBuilder::EntitySet` (builder
DSL), and delegate them on `SchemaBuilder::Endpoint` the way `supports_search?` already is.

Then gate the input schemas:

- `list_<Set>`: `odata_filter` only when `supports_filter?`; `odata_top` only when `supports_top?`;
  `odata_skip` only when `supports_skip?`; `odata_search` only when `supports_search?` (already the
  case); `odata_select` always (ungated — `$select` needs no hook).
- `count_<Set>`: `odata_filter` only when `supports_filter?`; `odata_search` only when
  `supports_search?` (already the case).
- New `odata_skiptoken` on `list_<Set>` only, only when `supports_skiptoken?`. Register it in
  `McpInputSchemas::QUERY_OPTION_ALIASES` as the alias for `$skiptoken` so
  `McpServerBuilder::QUERY_OPTION_SPELLINGS` translates a `tools/call` argument back to the OData
  `$skiptoken` spelling automatically.

Keep this task's argument *shapes* and descriptions exactly as they are today (`odata_select` stays
a `string`, no `minimum`, existing description strings) — task 2 changes those. `odata_skiptoken` is
a `string` in this task; task 2 gives it its description.

`get_`/`create_`/`update_`/`delete_` tools are untouched here. `$metadata` is untouched by the whole
PRD. REST execution is unchanged: hiding an argument from a tool schema must not change what
`Executor` honors or rejects.

**Likely files:**

- `lib/odata_duty.rb` (`EntitySet::Metadata` predicates)
- `lib/odata_duty/schema_builder/entity_set.rb`, `lib/odata_duty/schema_builder/endpoint.rb`
- `lib/odata_duty/mcp_input_schemas.rb` (aliases + gating), `lib/odata_duty/mcp_server_builder.rb`
  (pass the new capability flags through to the input-schema builders)
- Specs: `spec/odata_duty/entity_set/list_mcp_spec.rb`,
  `spec/odata_duty/entity_set/count_mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/list_mcp_spec.rb`,
  `spec/odata_duty/schema_builder/entity_set/count_mcp_spec.rb`

**Defining PRD excerpt:**

> **Current behavior:** `list_Products` on a set implementing only `collection` advertises
> `odata_filter`, `odata_select`, `odata_top`, `odata_skip`; three of the four raise
> `NoImplementationError` on use. **Expected behavior:** it advertises `odata_select` alone.
>
> ### Capability rules
>
> An entity set is **filterable** when its entity-set / resolver class defines any public instance
> method whose name begins with `od_filter_`. This deliberately counts `od_filter_or` on its own:
> such a set serves `a eq 1 or b eq 2` even though a single predicate fails, so some filtering
> genuinely works.
>
> The `od_filter_` prefix scan has no false positives from inheritance: neither
> `OdataDuty::EntitySet` nor `OdataDuty::SetResolver` defines any method matching that prefix (the
> only `od_*` method either base class provides is `od_next_link_skiptoken`), and the check excludes
> private methods, so nothing is counted that a consumer did not write as a public hook.
>
> The other gates reuse the existing per-hook rules: `od_top` for `$top`, `od_skip` for `$skip`,
> `od_skiptoken` for `$skiptoken`, `od_search` for `$search`. `$select` remains **ungated** — it
> needs no hook, since the projection happens regardless and `od_select` is only an optimisation
> callback.
>
> ### New argument name
>
> `odata_skiptoken` is a **coined** name, not an OData term — but it follows the existing,
> already-documented convention exactly: `$`-prefixed query-option names are illegal in Anthropic
> tool-schema property keys, so each is aliased as `odata_<option>`. It joins the established set
> `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip` and is translated back to
> OData `$skiptoken` before execution.
>
> ### `tools/call` round trips
>
> ```
> list_People {"odata_skiptoken": "5"}
>   -> GET /People?$skiptoken=5
> ```
>
> `NoImplementationError` for `$top`/`$skip`/`$skiptoken`/`$search`/`$filter` becomes unreachable
> *through MCP* for the gated cases, because the argument no longer exists to be passed. It remains
> reachable over REST.
>
> **Out:** `$metadata` is untouched — no change to `Capabilities.FilterRestrictions`,
> `SearchRestrictions`, or any other annotation.

**Dependencies:** none.

---

## - [x] Task 2 — MCP read-tool argument shapes and generated descriptions

**Task text:** Give the gated `list_`/`count_`/`get_` arguments their final shapes and generated
descriptions, on **both** DSLs.

- `odata_select` becomes `{"type": "array", "description": "Properties to return; omit for all.",
  "items": {"type": "string", "enum": [<entity type property names>]}}` on `list_`, `count_` (where
  it exists — `count_` has no `$select`, so this is `list_` and `get_`) and `get_`. The enum carries
  the entity type's property names only — no per-property descriptions.
- `McpServerBuilder` joins an `odata_select` array to the OData comma-separated `$select` spelling
  before execution; every other argument is translated as today.
- `odata_top` and `odata_skip` gain `"minimum": 0`.
- `odata_filter` gains the generated description:
  `"OData $filter expression; see the service instructions for the grammar. Filtering is supported
  for this entity set, but not every property or operator combination is necessarily implemented —
  an unsupported combination returns an error rather than an empty result. Property names are listed
  under odata_select. Example: user_name eq 'Alice'"`
- `odata_search`: `"Free-text $search expression; terms combined with AND, OR, NOT. Parenthesised
  groups are not supported."`
- `odata_top`: `"Maximum number of records to return."`;
  `odata_skip`: `"Number of records to skip before returning results."`
- `odata_skiptoken`: `"Continuation token for the next page. Take it from the $skiptoken query
  parameter of a prior response's @odata.nextLink."`
- `count_<Set>` gains descriptions where it had none: its `odata_filter` and `odata_search` carry the
  same text as `list_<Set>`.
- `get_<Set>`'s `odata_select` takes the same enum'd-array shape; its key property and `required`
  are unchanged.

Property `description:` values must continue to reach `inputSchema.properties.<name>.description`,
and an entity set's `description:` must continue to be appended to every tool description for that
set. `create_`/`update_`/`delete_` input schemas stay untouched.

If `McpInputSchemas` outgrows `Metrics/ModuleLength` (99), extract the query-option argument
definitions into a sibling module rather than adding an inline RuboCop disable.

**Likely files:**

- `lib/odata_duty/mcp_input_schemas.rb` (+ possibly a new sibling module for the argument
  definitions), `lib/odata_duty/mcp_server_builder.rb` (`$select` array join)
- Specs: `spec/odata_duty/entity_set/list_mcp_spec.rb`,
  `spec/odata_duty/entity_set/count_mcp_spec.rb`, `spec/odata_duty/entity_set/get_mcp_spec.rb`,
  `spec/odata_duty/entity_set/mcp_property_description_spec.rb` and the
  `spec/odata_duty/schema_builder/entity_set/**` counterparts

**Defining PRD excerpt:**

> ### `tools/list` — a set with no query-option hooks
>
> After:
>
> ```json
> {"name": "list_Products", "description": "List Products records",
>  "inputSchema": {"type": "object", "required": [], "properties": {
>    "odata_select": {"type": "array", "description": "Properties to return; omit for all.",
>                     "items": {"type": "string", "enum": ["id", "name"]}}}}}
> ```
>
> ### `tools/list` — a fully capable set
>
> ```json
> {"name": "list_People", "description": "List People records",
>  "inputSchema": {"type": "object", "required": [], "properties": {
>    "odata_filter": {"type": "string", "description":
>      "OData $filter expression; see the service instructions for the grammar. Filtering is supported for this entity set, but not every property or operator combination is necessarily implemented — an unsupported combination returns an error rather than an empty result. Property names are listed under odata_select. Example: user_name eq 'Alice'"},
>    "odata_select": {"type": "array", "description": "Properties to return; omit for all.",
>                     "items": {"type": "string", "enum": ["id", "user_name", "emails"]}},
>    "odata_search": {"type": "string", "description":
>      "Free-text $search expression; terms combined with AND, OR, NOT. Parenthesised groups are not supported."},
>    "odata_top":  {"type": "integer", "minimum": 0,
>                   "description": "Maximum number of records to return."},
>    "odata_skip": {"type": "integer", "minimum": 0,
>                   "description": "Number of records to skip before returning results."},
>    "odata_skiptoken": {"type": "string", "description":
>      "Continuation token for the next page. Take it from the $skiptoken query parameter of a prior response's @odata.nextLink."}}}}
> ```
>
> `count_People` gains descriptions where it had none, and its `odata_filter` is gated by the same
> rule:
>
> ```json
> {"name": "count_People", "description": "Count People records",
>  "inputSchema": {"type": "object", "required": [], "properties": {
>    "odata_filter": {"type": "string", "description": "…same text as list_People…"},
>    "odata_search": {"type": "string", "description": "…same text as list_People…"}}}}
> ```
>
> `get_People`'s `odata_select` takes the same enum'd-array shape; its key property and `required`
> are unchanged. `create_`/`update_`/`delete_` tools are untouched.
>
> Property `description:` values continue to reach `inputSchema.properties.<name>.description`, and
> an entity set's `description:` continues to be appended to every tool description for that set.
> `$select`'s enum carries names only, not per-property descriptions.
>
> ### `tools/call` round trips
>
> `odata_select` is joined to the OData comma-separated spelling; every other argument is translated
> as today.
>
> ```
> list_People {"odata_select": ["id", "user_name"], "odata_top": 2}
>   -> GET /People?$select=id,user_name&$top=2
>
> count_People {"odata_filter": "user_name eq 'Alice'"}
>   -> GET /People/$count?$filter=user_name eq 'Alice'   -> "1"
> ```
>
> ### Common error cases
>
> Arguments are validated by the MCP SDK against the tool input schema *before* the handler runs, and
> a failure is returned as a tool-error result (`isError: true`) carrying `"Invalid arguments: …"`:
>
> - **`odata_select` given a string** (e.g. `"id,user_name"` instead of `["id","user_name"]`) →
>   rejected by the SDK. The argument is strictly an array.
> - **`odata_select` naming an unknown property** → rejected by the SDK on the `enum`.
>   `UnknownPropertyError` is consequently no longer reachable through MCP `$select`; it remains
>   reachable through the REST `$select` and through `odata_filter` naming a non-existent property.
> - **`odata_top` / `odata_skip` given a negative integer** → rejected by the SDK on `minimum: 0`,
>   rather than reaching `InvalidQueryOptionError` as it does over REST.
> - **A missing required argument** (a `get_`/`update_`/`delete_` key) →
>   `"Missing required arguments: …"`, unchanged.
>
> **Out:** Structured/typed `$filter` arguments; the value stays a free-text OData expression.
> `create_`/`update_`/`delete_` tool input schemas.

**Dependencies:** task 1 (the gating and the `odata_skiptoken` alias must exist first).

---

## - [ ] Task 3 — Generated MCP server `instructions` describing the dialect

**Task text:** Replace the raw `instructions: schema.description` passed to `MCP::Server` with a
generated document: the schema `description:` first (when present), then a generated dialect
section. Applies to **both** DSLs (`OdataDuty::Schema.to_mcp_server` and
`SchemaBuilder::Schema#to_mcp_server` both route through `McpServerBuilder.build`).

Sections appear only when at least one entity set in the schema supports the capability — the
`$filter` paragraph needs a filterable set, the `$search` line needs an `od_search`, the paging line
needs an `od_skiptoken`. Aggregate over `schema.endpoints` using the task-1 predicates.

The exact target text (`\n`-separated, schema description separated from the dialect section by a
blank line):

```
This service exposes a subset of OData v4. Query options are passed to tools as `odata_*` arguments (e.g. `odata_filter` is OData `$filter`).

$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ne, gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with `or` is not supported, nor is parenthesised grouping. Functions (contains, startswith, tolower, …), arithmetic and `not` are not supported. String literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO 8601 (2024-01-31, 2024-01-31T00:00:00+00:00).
$search: terms combined with AND, OR, NOT. Parenthesised groups are not supported.
Paging: pass odata_skiptoken with the $skiptoken value from a prior response's @odata.nextLink.
$orderby, $expand, $apply, $compute and $count=true are not supported.

Each tool advertises only the query options its entity set supports.
```

**Behavior change to implement deliberately:** `instructions` was previously exactly
`schema.description` and the key was omitted when that was `nil`. It is now **always present** — a
schema with no `description:` returns the dialect text alone. The existing spec asserting the key is
omitted must be replaced, not deleted silently.

Note the existing `McpServerBuilder.build` comment about relying on the `mcp` gem `.compact`-ing a
nil `instructions:`; that rationale no longer applies and the comment should be updated or removed.

If `McpServerBuilder` outgrows `Metrics/ModuleLength` (99), put the instructions builder in its own
file (e.g. `lib/odata_duty/mcp_instructions.rb`) rather than adding an inline disable.

**Likely files:**

- `lib/odata_duty/mcp_server_builder.rb`, probably a new `lib/odata_duty/mcp_instructions.rb`
- Specs: `spec/odata_duty/schema_builder/schema_mcp_instructions_spec.rb` (rewrite) and a new
  class-DSL counterpart under `spec/odata_duty/entity_set/`

**Defining PRD excerpt:**

> ### `initialize` — server `instructions`
>
> The schema `description:` comes first, then a generated dialect section. Sections appear only when
> at least one entity set in the schema supports the capability.
>
> ```json
> {"jsonrpc": "2.0", "id": 1, "result": {
>   "protocolVersion": "2025-06-18",
>   "capabilities": {"tools": {}},
>   "serverInfo": {"name": "Test OData API", "version": "1.0.0"},
>   "instructions": "Attendee records for the spring conference.\n\nThis service exposes a subset of OData v4. Query options are passed to tools as `odata_*` arguments (e.g. `odata_filter` is OData `$filter`).\n\n$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ne, gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with `or` is not supported, nor is parenthesised grouping. Functions (contains, startswith, tolower, …), arithmetic and `not` are not supported. String literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO 8601 (2024-01-31, 2024-01-31T00:00:00+00:00).\n$search: terms combined with AND, OR, NOT. Parenthesised groups are not supported.\nPaging: pass odata_skiptoken with the $skiptoken value from a prior response's @odata.nextLink.\n$orderby, $expand, $apply, $compute and $count=true are not supported.\n\nEach tool advertises only the query options its entity set supports."}}
> ```
>
> For a schema whose sets implement no `od_search`, the `$search` line is absent; with no filterable
> set, the `$filter` paragraph is absent; with no `od_skiptoken`, the paging line is absent.
>
> **Behavior change:** `instructions` was previously exactly `schema.description`, and the key was
> omitted when that was `nil`. It is now always present — a schema with no `description:` returns the
> dialect text alone.
>
> **Out:** `$orderby`, `$expand`, `$apply` support — named as unsupported in `instructions`, not
> implemented. MCP resources (the server stays tools-only), tool `annotations` (`readOnlyHint` etc.),
> and `outputSchema`. Rewriting error messages to teach the supported surface.

**Dependencies:** task 1 (capability predicates).

---

## - [ ] Task 4 — `$oas2` collection parameters: gate `$filter`, bound `$top`/`$skip`, enum `$select`

**Task text:** In the `$oas2` collection `GET` parameter list:

- Gate `$filter` on the same `supports_filter?` rule as MCP (any public `od_filter_*` method), so a
  set with no filter hook loses the parameter — alongside the `$top`/`$skip`/`$skiptoken`/`$search`/
  `$count` gating that already applies.
- Add `"minimum": 0` to `$top` and `$skip`.
- Add `items.enum` of the entity type's property names to `$select`.

State in the commit message that this task is **builder-DSL only**: `OAS2.build_json` takes a
`SchemaBuilder::Schema` (it reads `host`/`scheme`/`base_path`/`collection_entity_sets`, none of which
the class-based `OdataDuty::Schema` exposes), so there is no class-DSL `$oas2` path to mirror.

REST execution must stay unchanged: hiding a parameter from `$oas2` does not stop the service from
honoring or rejecting it.

**Likely files:**

- `lib/odata_duty/oas2/collection_get_path.rb` (the `$select` enum is per-entity-type, so the frozen
  `COLLECTION_PARAMETERS` constant needs restructuring — keep methods under `MethodLength` 13)
- Specs: `spec/odata_duty/oas2/collection_scalars_oas2_spec.rb`,
  `spec/odata_duty/oas2/full_document_spec.rb`, and/or a new focused spec under
  `spec/odata_duty/oas2/`

**Defining PRD excerpt:**

> ### `$oas2`
>
> `GET /Products` loses its `$filter` parameter (the set has no `od_filter_*` hook), alongside the
> `$top`/`$skip`/`$skiptoken`/`$search`/`$count` gating that already applied. On sets that keep them,
> `$top` and `$skip` gain `"minimum": 0` and `$select` gains an `items.enum` of the entity type's
> property names:
>
> ```json
> {"name": "$select", "in": "query", "type": "array", "collectionFormat": "csv",
>  "items": {"type": "string", "enum": ["id", "user_name", "emails"]},
>  "description": "Comma-separated list of properties to return"},
> {"name": "$top", "in": "query", "type": "integer", "minimum": 0,
>  "description": "Number of results to return"}
> ```
>
> REST execution is unchanged throughout: hiding a parameter from `$oas2` does not stop the service
> from honoring or rejecting it.

**Dependencies:** task 1 (`supports_filter?`).

---

## - [ ] Task 5 — Documentation

**Task text:** Update the guides named in the PRD's Documentation impact section, in the existing
style of each guide. No production-code change; `bundle exec rake` must stay green.

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

`README.md` needs no change: it carries no MCP or query-option examples. Do not bump
`spec.version` in `odata_duty.gemspec`.

**Defining PRD excerpt:**

> ## Documentation impact
>
> Extend, in the existing style:
>
> - **`doc/using_mcp.md`** — rewrite the `list_`/`count_`/`get_` bullets for the gated parameter
>   sets, the new `odata_skiptoken`, the array-shaped `odata_select`, and the generated
>   `instructions`.
> - **`doc/using_descriptions.md`** — `instructions` is no longer just the schema `description:`;
>   record the composition order and that the key is now always present.
> - **`doc/using_paging.md`** — server-driven paging is now reachable from MCP.
> - **`doc/using_oas2.md`** — `$filter` is now capability-gated; `$top`/`$skip` bounds and the
>   `$select` enum.
> - **`doc/using_filter.md`** — note that filter capability is inferred from any `od_filter_*` hook
>   and drives what MCP and `$oas2` advertise.
> - **`AGENTS.md`** (`CLAUDE.md` is its symlink) — update the `$filter`, `$select`, Paging and MCP
>   entries in the Features index so they still match the guides above.
>
> `README.md` needs no change: it carries no MCP or query-option examples.

**Dependencies:** tasks 1–4 (documents their shipped behavior).
