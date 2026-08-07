# Build plan: MCP-safe tool schema keys

PRD: [mcp-safe-tool-schema-keys.md](mcp-safe-tool-schema-keys.md)

Both DSLs (`OdataDuty::Schema#to_mcp_server` and `OdataDuty::SchemaBuilder`'s
`to_mcp_server`) funnel into the exact same `OdataDuty::McpServerBuilder.build(schema)` /
`OdataDuty::McpInputSchemas` code path (confirmed by reading `lib/odata_duty.rb:307-309`
and `lib/odata_duty/schema_builder.rb:99-101`). So production code for this PRD is
DSL-agnostic and lives in `lib/odata_duty/mcp_input_schemas.rb` and
`lib/odata_duty/mcp_server_builder.rb` — no class-DSL-only or builder-DSL-only production
change is expected. Tests still land in **both** spec trees per repo convention (existing
MCP specs are already duplicated file-for-file across `spec/odata_duty/entity_set/**` and
`spec/odata_duty/schema_builder/entity_set/**`).

## Task 1 — Rename the five query-option MCP keys to `odata_*` aliases (Half 1)

**Status:** - [ ]

**Full task text:** Add a single shared mapping between the OData system-query-option
spelling (`$filter`, `$select`, `$search`, `$top`, `$skip`) and its Anthropic-safe MCP alias
(`odata_filter`, `odata_select`, `odata_search`, `odata_top`, `odata_skip`). Use it in
`McpInputSchemas` so `list_<Set>`/`count_<Set>`/`get_<Set>` input schemas emit the
`odata_*` keys instead of the `$`-prefixed ones. Use the *same* mapping in
`McpServerBuilder` to translate incoming `tools/call` arguments back to the OData spelling
before they reach `Executor`, so the two directions never drift independently. Only the
five reserved keys are translated — record-key arguments (e.g. `get_<Set>`'s own key
property) and create/update property values pass through unchanged. Update every existing
spec (both DSL trees) that asserts on the old `$`-prefixed keys appearing in an MCP
`inputSchema.properties` or as a `tools/call` argument, so the suite reflects the new
spelling end-to-end. Do **not** touch `spec/odata_duty/*/entity_set/search_spec.rb`'s
non-MCP `describe` blocks that call `schema.execute`/`schema.create` directly with
`query_options: { '$search' => ... }` — those exercise the REST/Executor path, which this
PRD does not change; only the nested `describe 'mcp'` blocks in those files use the tool
surface and need updating.

**Definition of done (PRD excerpt):**
- Table: `$filter`→`odata_filter`, `$select`→`odata_select`, `$search`→`odata_search`,
  `$top`→`odata_top`, `$skip`→`odata_skip`. "This is a single shared mapping, used both
  when building the schema and when translating a tool call back into OData query
  options — the two directions never drift independently."
- "Calling a tool with the new key names still reaches `Executor` as the original OData
  query option — a `tools/call` for `list_People` with `{"odata_filter": "name eq
  'Alice'"}` produces the exact same result as `GET /People?$filter=name eq 'Alice'`."
- "A `get_People` call's own record-key argument (e.g. `{"id": "1", "odata_select":
  "name"}`) is unaffected: only the five reserved keys above are translated back to their
  OData spelling before reaching `Executor`; every other argument (record keys,
  create/update property values) passes through as today."
- Expected `tools/list` shape (see PRD's "`tools/list` after the fix" JSON): `list_People`'s
  `inputSchema.properties` uses `odata_filter`/`odata_select`/`odata_search`/`odata_top`/
  `odata_skip` with their existing descriptions, `required: []`.

**Likely files:**
- `lib/odata_duty/mcp_input_schemas.rb` (add the mapping constant; use aliased keys in
  `count_input_schema`, `list_input_schema`, `get_input_schema`)
- `lib/odata_duty/mcp_server_builder.rb` (`define_tool`/`run_tool`: translate the 5 keys
  back to `$`-spelling before building `query_options`)
- `spec/odata_duty/entity_set/list_mcp_spec.rb`, `count_mcp_spec.rb`, `get_mcp_spec.rb`,
  `schema_to_mcp_server_spec.rb`, `search_spec.rb` (mcp section only)
- `spec/odata_duty/schema_builder/entity_set/list_mcp_spec.rb`, `count_mcp_spec.rb`,
  `get_mcp_spec.rb`, `search_spec.rb` (mcp section only)

**Depends on:** nothing (first task).

## Task 2 — Build-time validation of every generated MCP identifier (Half 3)

**Status:** - [ ]

**Full task text:** Add `OdataDuty::InvalidMcpIdentifierError` (an `ArgumentError`
subclass, alongside `InvalidNCNamesError`, in `lib/odata_duty/errors.rb`). In
`McpServerBuilder`, after the Task-1 rename is applied, validate every JSON Schema property
key and every tool name about to be emitted, in schema declaration order across endpoints
and, within an endpoint, in the order `list`, `count`, `get`, `create`, `update`, `delete`
— raising `InvalidMcpIdentifierError` on the *first* violation found, before the server
object is returned. Two independent checks: (1) every `input_schema.properties` key
(the `odata_*` aliases and every entity property name used verbatim, including the key
property) must match `\A[a-zA-Z0-9_.-]{1,64}\z`; (2) every tool name (`list_<Set>`,
`count_<Set>`, `get_<Set>`, `create_<Set>`, `update_<Set>`, `delete_<Set>`) must match
`\A[a-zA-Z0-9_-]{1,64}\z`. Also cover the residual collision case: an entity property
literally named `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip`
silently overwriting the reserved query-option key when both land in the same
`list_`/`count_`/`get_` properties hash (today only `get_` mixes a property — the key
property — with a reserved alias, since `list_`/`count_` schemas contain only the five
reserved keys; detect the collision explicitly rather than relying on the regex, since
`odata_select` itself is a valid identifier and would otherwise overwrite silently). Add
tests to both DSL spec trees for: a non-ASCII property name reaching a `create_`/`update_`/
`get_`/`delete_` schema, an oversized property name, an entity-set name that pushes a tool
name over 64 characters, and the reserved-key collision. Existing MCP specs (typical,
ASCII, short names) must keep passing unchanged — this is a new guard on already-valid
schemas, not a behavior change for them.

**Definition of done (PRD excerpt):**
- "`to_mcp_server` validates every JSON Schema property key and every tool name it is
  about to emit against the Anthropic-safe pattern, **after** the query-option rename
  above is applied."
- Property-key pattern: `\A[a-zA-Z0-9_.-]{1,64}\z`. Tool-name pattern:
  `\A[a-zA-Z0-9_-]{1,64}\z`.
- "On violation, `to_mcp_server` raises `OdataDuty::InvalidMcpIdentifierError` (a new
  `ArgumentError` subclass, alongside `InvalidNCNamesError`) naming the entity set, the
  tool or property involved, and the value that failed. Validation walks endpoints in
  schema declaration order and, within an endpoint, tools in the order `list`, `count`,
  `get`, `create`, `update`, `delete`, raising on the first violation found."
- Non-ASCII example:
  ```
  OdataDuty::InvalidMcpIdentifierError:
  PersonType property "日本語" cannot be used as an MCP tool input key —
  it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)
  ```
- Oversized tool-name example:
  ```
  OdataDuty::InvalidMcpIdentifierError:
  tool name "list_ThisIsAnExtremelyLong...Set" is 79 characters — MCP tool names must
  match /\A[a-zA-Z0-9_-]{1,64}\z/
  ```
- Common Error Cases: "Covers: a non-ASCII or over-64-character entity property name
  reaching a `create_`/`update_`/`get_`/`delete_` schema; an entity-set name that pushes a
  generated tool name over 64 characters or outside its allowed character set; and the
  residual case where an entity property is literally named
  `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip` and collides with
  the reserved query-option key in a `list_`/`count_`/`get_` schema."
- Out of scope reminder: do not change `OdataDuty::Property::NAME_REGEXP` or add
  transliteration/truncation — always fail loudly instead.

**Likely files:**
- `lib/odata_duty/errors.rb` (new `InvalidMcpIdentifierError`)
- `lib/odata_duty/mcp_server_builder.rb` (validation entry point, walking endpoints/tools
  in the required order)
- `lib/odata_duty/mcp_input_schemas.rb` (if the collision check is more naturally built
  alongside schema construction)
- New or extended specs in both `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/entity_set/**` (e.g. alongside `schema_to_mcp_server_spec.rb`
  / `get_mcp_spec.rb`, or a new `invalid_mcp_identifier_spec.rb` in each tree)

**Depends on:** Task 1 (validates the post-rename `odata_*` keys, and the collision check
is against those aliases).

## Task 3 — Documentation impact

**Status:** - [ ]

**Full task text:** Extend `doc/using_mcp.md` per the PRD's Documentation impact section:
update the "Tools" section's per-tool key lists for `list_<Set>`, `count_<Set>`,
`get_<Set>` to show `odata_filter`/`odata_select`/`odata_search`/`odata_top`/`odata_skip`
in place of the `$`-prefixed spellings, and note the round trip back to the OData query
option. Add `OdataDuty::InvalidMcpIdentifierError` to `doc/using_mcp.md`'s "Common Error
Cases" section, with the two triggering conditions (invalid property name, invalid/oversized
tool name) and a short example. Also update the one-line `## Features` index entry for
"MCP server" in `CLAUDE.md` (currently reads "...reads inferred as `list_/get_/count_<Set>`
tools (`$search` on list/count)...") so it no longer references the old `$`-prefixed
spelling now that the tool surface uses `odata_*` keys.

**Definition of done (PRD excerpt):**
> Extend `doc/using_mcp.md`:
> - Update the "Tools" section's per-tool key lists (`list_<Set>`, `count_<Set>`,
>   `get_<Set>`) to show `odata_filter`/`odata_select`/`odata_search`/`odata_top`/
>   `odata_skip` in place of the `$`-prefixed spellings, and note the round trip back to
>   the OData query option.
> - Add `OdataDuty::InvalidMcpIdentifierError` to "Common Error Cases", with the two
>   triggering conditions (property name, tool name) and a short example.

**Likely files:** `doc/using_mcp.md`, `CLAUDE.md` (`## Features` index line only).

**Depends on:** Tasks 1 and 2 (documents their combined, final behavior).
