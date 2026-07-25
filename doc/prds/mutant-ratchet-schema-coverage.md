# PRD: Mutation-verify the Schema entry-point API (shrink the `.mutant.yml` ratchet)

## 1. Summary
Remove 33 `.mutant.yml` ignore entries covering the top-level `OdataDuty::Schema` /
`Schema::Metadata` (class DSL) and `OdataDuty::SchemaBuilder::Schema` (builder DSL) methods, and
add public-API tests that kill every surviving mutation so mutation CI stays green with those
subjects gated. This is a test-quality cleanup for the gem's primary entry points — no new
consumer capability.

## 2. Goal / Problem
`.mutant.yml` is a debt ratchet (`spec/using_mutant.md`): listed subjects are skipped by mutation
CI entirely, so their behavior is *run* (100% line/branch coverage) but not *verified*. The Schema
entry points are the gem's front door — `metadata_xml`, `index_hash`, `execute`, `create`,
`update`, `delete`, `to_mcp_server`, and the schema-level declarations that feed them. Leaving them
un-gated means a regression that changes their observable output could pass CI. Removing the entries
closes that gap.

- **Current behavior:** mutant skips these 33 subjects; a surviving mutation in any of them does not
  fail CI.
- **Expected behavior:** the entries are gone; `bundle exec mutant run` reports zero survivors for
  all 33 subjects, gated on every future PR.

## 3. What it enables
- As a gem maintainer, I get a mutation gate on the public Schema entry points, so a change that
  silently alters `$metadata`, the index document, GET/POST/PATCH/DELETE dispatch, or the MCP server
  is caught.
- As a gem consumer, the documented behavior of `Schema` / `SchemaBuilder::Schema` is pinned by
  tests, reducing the chance of a surprise regression across releases.
- **Scope limit:** only the 33 listed subjects. The other ratchet entries stay untouched. No
  behavior changes unless a survivor is best killed by *accepting* a mutation (a simplifying
  refactor with identical observable output).

## 4. External API (surface that must be verified — all pre-existing)
No new names. Each subject maps to an existing public entry point and its OData output. Tests must
exercise these **only through the public API** (`AGENTS.md`): define real schemas/resolvers and
assert observable output.

**Class DSL — `OdataDuty::Schema` (`spec/odata_duty/entity_set/**`):**

```ruby
class MySchema < OdataDuty::Schema
  namespace 'My.Service'      # → EDMX Schema Namespace / MCP server name
  title 'My Service'          # → index + OAS2 title
  version '1.0'               # → EDMX edmx:DataServices / OData-Version surface
  base_url 'https://host/svc' # → absolute URLs in index + collection payloads
  entity_sets [UsersSet]      # → EntityContainer EntitySet entries
end

MySchema.metadata_xml               # → $metadata EDMX XML
MySchema.index_hash(metadata_url)   # → OData service index document (JSON hash)
MySchema.endpoints                  # → the endpoint list backing the index
MySchema.execute(url, context:, query_options:) # → GET: collection / individual / $count
MySchema.create(url, context:, query_options:)   # → POST create
MySchema.update(url, context:, query_options:)   # → PATCH partial-merge update
MySchema.delete(url, context:, query_options:)   # → DELETE
MySchema.to_mcp_server              # → MCP server object (tools/resources over JSON-RPC)
```

`Schema::Metadata#*` (`version`, `title`, `namespace`, `entity_sets`, `metadata_types`,
`entity_types`, `complex_types`, `enum_types`, `singletons`, `endpoints`, `check_names`) are the
metadata view walked by the renderers; each is verified indirectly by asserting the `$metadata` /
index / `$oas2` output it shapes — including `check_names` raising on a duplicate type name.

**Builder DSL — `OdataDuty::SchemaBuilder::Schema` (`spec/odata_duty/schema_builder/**`):**

```ruby
schema = OdataDuty::SchemaBuilder.build(
  namespace: 'My.Service', host: 'host', scheme: 'https', base_path: '/svc'
) do |s|
  s.add_entity_type(name: 'User') { |t| t.property_ref 'id', String }
  s.add_entity_set(name: 'Users', entity_type: 'User', resolver: 'UsersResolver')
end

schema.metadata_xml     # → $metadata EDMX XML
schema.index_hash       # → OData service index document
schema.execute/create/update/delete(url, context:, query_options:)
schema.to_mcp_server
schema.inspect          # → debug string listing containers/types
```

Subjects `initialize`, `all_containers`, `complex_types`, `entity_sets`, `individual_entity_sets`,
`execute`, `create`, `update`, `delete`, `inspect` must each have their observable result pinned —
e.g. `individual_entity_sets` reflected by which sets expose `Users(id)` in `$metadata`/index and
answer `execute`.

## 5. Behavior & expected I/O (what tests must pin)
Representative assertions the mutation gate requires (each kills a class of survivors):

- **`namespace`/`version`/`title`/`base_url`** — assert the exact string appears in `$metadata` XML
  and/or `index_hash`; mutating the getter/setter or a default must change output.
- **`entity_sets` dedup** — `entity_sets` applies `.uniq`; a schema declaring the same set twice must
  yield one container entry.
- **`execute` dispatch** — same URL family must route: `Users` → collection, `Users(1)` →
  individual, `Users/$count` → count; assert each distinct result so a mutant that collapses the
  dispatch survives nowhere.
- **`create`/`update`/`delete`** — POST returns the created entity, PATCH partial-merges, DELETE
  removes; assert the observable effect and the returned payload.
- **`index_hash`** — asserts `@odata.context` equals the passed metadata URL and each endpoint's
  `name`/`kind`/`url`.
- **`to_mcp_server`** — resulting server lists the expected tools/resources for the declared sets
  (and a `search_*` tool only when the resolver defines `od_search`).
- **`inspect`** (builder) — returns a string containing the namespace, base path, container names,
  and type names.

## 6. Common error cases (behavior that must also be verified)
- `Schema::Metadata#check_names` raises `"Duplicate <Name> type"` when two types share a name.
- `execute`/`create`/`update`/`delete` propagate the existing framework errors for their
  conditions: `ResourceNotFoundError` (unknown URL / missing individual), `NoImplementationError`
  (hook absent), `InvalidQueryOptionError` / `InvalidValue` (bad query option or payload). Tests must
  assert at least the error classes already documented for these paths so a mutant that swallows or
  reclassifies them dies.

## 7. Scope
- **In:** the 33 listed subjects; both DSLs and both spec trees (`spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/**`); public-API tests only; accepting a mutation (source
  simplification with identical observable output) where that is the correct kill per
  `spec/using_mutant.md`.
- **Out:** the remaining `.mutant.yml` entries; any change to consumer-facing behavior or new API;
  adding ignore entries (forbidden by the ratchet).

The 33 subjects to remove from `.mutant.yml`:

```
OdataDuty::Schema.base_url
OdataDuty::Schema.create
OdataDuty::Schema.delete
OdataDuty::Schema.endpoints
OdataDuty::Schema.entity_sets
OdataDuty::Schema.execute
OdataDuty::Schema.index_hash
OdataDuty::Schema.metadata_xml
OdataDuty::Schema.namespace
OdataDuty::Schema.title
OdataDuty::Schema.to_mcp_server
OdataDuty::Schema.update
OdataDuty::Schema.version
OdataDuty::Schema::Metadata#check_names
OdataDuty::Schema::Metadata#complex_types
OdataDuty::Schema::Metadata#endpoints
OdataDuty::Schema::Metadata#entity_types
OdataDuty::Schema::Metadata#enum_types
OdataDuty::Schema::Metadata#metadata_types
OdataDuty::Schema::Metadata#namespace
OdataDuty::Schema::Metadata#singletons
OdataDuty::Schema::Metadata#title
OdataDuty::Schema::Metadata#version
OdataDuty::SchemaBuilder::Schema#all_containers
OdataDuty::SchemaBuilder::Schema#complex_types
OdataDuty::SchemaBuilder::Schema#create
OdataDuty::SchemaBuilder::Schema#delete
OdataDuty::SchemaBuilder::Schema#entity_sets
OdataDuty::SchemaBuilder::Schema#execute
OdataDuty::SchemaBuilder::Schema#individual_entity_sets
OdataDuty::SchemaBuilder::Schema#initialize
OdataDuty::SchemaBuilder::Schema#inspect
OdataDuty::SchemaBuilder::Schema#update
```

## 8. Documentation impact
No consumer guide changes. This tracks against `spec/using_mutant.md` (the ratchet process); the
entry-count noted there should be updated to reflect the removals when implemented. No new `doc/`
guide.

## 9. Open questions
- If a survivor is best killed by *accepting* a mutation (refactoring `lib/`), that touches source
  beyond `.mutant.yml`. Assumed in-scope for `/build`; flag any such refactor in review since it
  changes internal code even when observable output is unchanged.
