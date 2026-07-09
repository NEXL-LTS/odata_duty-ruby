# Retire the `$oas2` renderer mutation-testing debt

## Summary

Remove all 38 `OdataDuty::OAS2*` entries from `.mutant.yml`'s ignore list by pinning the
complete `$oas2` (Swagger 2.0) document as spec-asserted public contract. No output changes —
this is a pure pin. The externally visible changes are specs, an optional README line, and any
accept-mutation simplifications inside the renderer.

```yaml
- "OdataDuty::OAS2#add_collection_paths"
- "OdataDuty::OAS2#add_complex_definitions"
- "OdataDuty::OAS2#add_enum_definitions"
- "OdataDuty::OAS2#add_error_definition"
- "OdataDuty::OAS2#add_individual_paths"
- "OdataDuty::OAS2#add_request_body_definitions"
- "OdataDuty::OAS2#initialize"
- "OdataDuty::OAS2#register_definition"
- "OdataDuty::OAS2#wrap_context"
- "OdataDuty::OAS2.build_json"
- "OdataDuty::OAS2::CollectionPostPath#create_schema"
- "OdataDuty::OAS2::CollectionPostPath#entity_type_schema"
- "OdataDuty::OAS2::CollectionPostPath#initialize"
- "OdataDuty::OAS2::CollectionPostPath#operation_id"
- "OdataDuty::OAS2::CollectionPostPath#parameters"
- "OdataDuty::OAS2::CollectionPostPath#produces"
- "OdataDuty::OAS2::CollectionPostPath#responses"
- "OdataDuty::OAS2::CollectionPostPath.request_body_definition"
- "OdataDuty::OAS2::CollectionPostPath.to_oas2"
- "OdataDuty::OAS2::IndividualDeletePath#id_type"
- "OdataDuty::OAS2::IndividualDeletePath#initialize"
- "OdataDuty::OAS2::IndividualDeletePath#operation_id"
- "OdataDuty::OAS2::IndividualDeletePath#parameters"
- "OdataDuty::OAS2::IndividualDeletePath#responses"
- "OdataDuty::OAS2::IndividualDeletePath.to_oas2"
- "OdataDuty::OAS2::IndividualGetPath#oas2_parameters"
- "OdataDuty::OAS2::IndividualGetPath#oas2_responses"
- "OdataDuty::OAS2::IndividualGetPath#to_oas2"
- "OdataDuty::OAS2::IndividualPatchPath#entity_type_schema"
- "OdataDuty::OAS2::IndividualPatchPath#id_type"
- "OdataDuty::OAS2::IndividualPatchPath#initialize"
- "OdataDuty::OAS2::IndividualPatchPath#operation_id"
- "OdataDuty::OAS2::IndividualPatchPath#parameters"
- "OdataDuty::OAS2::IndividualPatchPath#produces"
- "OdataDuty::OAS2::IndividualPatchPath#responses"
- "OdataDuty::OAS2::IndividualPatchPath#update_schema"
- "OdataDuty::OAS2::IndividualPatchPath.request_body_definition"
- "OdataDuty::OAS2::IndividualPatchPath.to_oas2"
```

## Goal / Problem

Measured 2026-07-09 (entries temporarily removed, run scoped to `OdataDuty::OAS2*`):
**38 subjects, 1211 mutations, 195 killed, 1016 alive — 16.10% coverage.**

The root cause is **test selection, not assertion gaps**. Mutant's rspec integration maps tests
to subjects via the constant named in `RSpec.describe`, and only one spec file —
`spec/odata_duty/schema_builder/entity_set/collection_scalars_oas2_spec.rb`, 7 tests —
describes `OdataDuty::OAS2`. The substantial existing `$oas2` specs (the `create/oas2_spec.rb`,
`update/oas2_spec.rb`, `delete/oas2_spec.rb`, `computed_oas2_spec.rb` files in both trees, plus
`$oas2` sections inside `search_spec.rb` and `schema_builder_spec.rb`) describe
`OdataDuty::EntitySet` or `OdataDuty::SchemaBuilder`, so mutant never selects them for these
subjects — their assertions count for nothing here. The one correctly-anchored file is how
`OAS2::CollectionGetPath` (absent from the ignore list) was already cleaned; it is the template.

A secondary finding: `$oas2` is a **builder-DSL-only** output today. Every `$oas2` spec in both
trees builds its schema with `OdataDuty::SchemaBuilder.build`, because the class-based `Schema`
has no `host` / `scheme` / `base_path` and cannot feed `OAS2.build_json`. The usual
"mirror both DSL trees" rule therefore does not apply to this PRD.

## What it enables

- As a gem consumer generating a client from `$oas2`, the operationIds, response codes,
  definition names, and parameter shapes I codegen against are documented, spec-asserted
  contract that cannot silently change.
- As a gem consumer, one full-document spec shows me the entire `$oas2` output for a realistic
  schema — complete reference documentation in the suite.
- As a maintainer, every method of the `$oas2` renderer is mutation-gated; regressions in the
  document shape fail CI.

## External API

**No new DSL surface.** The public entry point is:

```ruby
OdataDuty::OAS2.build_json(schema)                    # as in the README's Rails controller
OdataDuty::OAS2.build_json(schema, context: request)  # optional request context
```

It accepts **builder-DSL schemas only**; passing a class-based `Schema` raises `NoMethodError`
(unchanged — adding class-DSL support is out of scope). Both invocation forms are pinned: the
`context:` keyword defaults to `nil` and the document must render without one.

A representative schema exercising every renderer:

```ruby
class TripsResolver < OdataDuty::SetResolver
  def od_after_init = @records = TRIPS
  def collection = @records
  def individual(id) = @records.find { |t| t.id == id }
  def create(input) = Trip.create(input)
  def update(id, input) = Trip.update(id, input)
  def delete(id) = Trip.delete(id)
  def count = @records.size
  def od_search(expression) = ...
  def od_top(top) = ...
  def od_skip(skip) = ...
  def od_skiptoken(token) = ...
end

class AuditLogsResolver < OdataDuty::SetResolver
  def od_after_init = @records = LOGS
  def collection = @records
  def individual(id) = @records.find { |l| l.id == id }
end

schema = OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                        base_path: '/api') do |s|
  s.title = 'Sample API'
  s.version = '1.0'
  trip = s.add_entity_type(name: 'Trip') do |et|
    et.property_ref 'id', Integer
    et.property 'name', String, nullable: false
    et.property 'status', TripStatus                       # an enum type
    et.property 'created_at', DateTime, mutability: :computed
  end
  log = s.add_entity_type(name: 'AuditLog') do |et|
    et.property_ref 'id', String
    et.property 'entry', String
  end
  s.add_entity_set(entity_type: trip, resolver: 'TripsResolver')
  s.add_entity_set(entity_type: log, resolver: 'AuditLogsResolver')
end
```

### The pinned document contract

All field names below use Swagger 2.0 spelling (`swagger`, `info`, `host`, `schemes`,
`basePath`, `paths`, `definitions`, `operationId`, `produces`, `parameters`, `responses`);
OData query options keep their OData spelling (`$filter`, `$select`, …). The operationId
patterns and `<EntityType>Create` / `<EntityType>Update` definition names are **coined** by
this gem (it does not follow the OASIS OData-to-OpenAPI mapping) and become pinned contract.

- **Skeleton** — `"swagger" => "2.0"`, `host`, `schemes => [scheme]`, `basePath`;
  `info.version` / `info.title` appear only when the schema sets `version` / `title`.
- **Definitions** — `Error` (`code`, `message`, `target` with `x-nullable`); one definition per
  enum, complex, and entity type, named after the type. For each set supporting `create`:
  `<EntityType>Create` — properties settable on create, `required` = the non-nullable among
  them, the `required` key omitted when that list is empty. For each set supporting `update`:
  `<EntityType>Update` — properties settable on update, never a `required` key. This is the
  same capability inference as `Capabilities.InsertRestrictions` / `UpdateRestrictions`
  (see `doc/using_create_update_and_delete.md`, `doc/using_mutability.md`).
- **Paths** — `/<url>`: GET always, POST iff the resolver defines `create`.
  `/<url>({id})`: GET iff `individual`, PATCH iff `update`, DELETE iff `delete`.
- **Operations** —
  - operationIds: `GetCollectionOf<Name>`, `GetIndividual<Name>ById`, `Create<Name>`,
    `Update<Name>`, `Delete<Name>`.
  - `produces => ['application/json']` on GET/POST/PATCH; DELETE has no `produces` key.
  - The `id` path parameter is `type => 'integer'` when the `property_ref` key is `Integer`,
    else `'string'` — on GET-individual, PATCH, and DELETE alike.
  - POST and PATCH each take one `body` parameter, `required => true`, whose schema `$ref`s
    the `<EntityType>Create` / `<EntityType>Update` definition.
  - Collection GET advertises `$filter` and `$select` always, and `$top` / `$skip` / `$count` /
    `$skiptoken` / `$search` only when the resolver defines `od_top` / `od_skip` / `count` /
    `od_skiptoken` / `od_search`; each parameter's `description` string is pinned verbatim.
  - Responses: collection GET 200 (value array + `@odata.nextLink` / `@odata.count`);
    individual GET 200 (`$ref` to the entity definition); POST **both** 200 `Success` and
    201 `Created`, each `$ref`ing the full entity definition; PATCH 200 `Success`;
    DELETE 204 `No Content` with no schema. Every operation carries the
    `default => { 'description' => 'Unexpected error', schema $ref #/definitions/Error }`
    response.

## Behavior & expected I/O

The backbone is a **full-document pin**: one exact-equality assertion of the entire
`build_json` output for the representative schema above. Abridged:

```json
{
  "swagger": "2.0",
  "info": { "version": "1.0", "title": "Sample API" },
  "host": "localhost", "schemes": ["https"], "basePath": "/api",
  "paths": {
    "/Trips": { "get": { "operationId": "GetCollectionOfTrips", "...": "all 7 query params" },
                "post": { "operationId": "CreateTrips",
                          "responses": { "200": {}, "201": {}, "default": {} } } },
    "/Trips({id})": { "get": { "operationId": "GetIndividualTripsById",
                               "parameters": [{ "name": "id", "type": "integer" }] },
                      "patch": { "operationId": "UpdateTrips" },
                      "delete": { "operationId": "DeleteTrips",
                                  "responses": { "204": {}, "default": {} } } },
    "/AuditLogs": { "get": { "...": "only $filter and $select advertised" } },
    "/AuditLogs({id})": { "get": { "parameters": [{ "name": "id", "type": "string" }] } }
  },
  "definitions": {
    "Error": {}, "Trip": {}, "AuditLog": {}, "TripStatus": {},
    "TripCreate": { "properties": { "name": {}, "status": {} }, "required": ["name"] },
    "TripUpdate": { "properties": { "name": {}, "status": {} } }
  }
}
```

Targeted specs on top pin each behavior readably: `info` empty when the schema sets no
`version` / `title`; POST/PATCH/DELETE and `<EntityType>Create` / `<EntityType>Update`
definitions absent for the read-only set; `required` omitted when every creatable property is
nullable; the id-type variants; the resolver-gated collection parameters.

### Spec anchoring — the decisive mechanism

Every example group asserting `OAS2.build_json` output is re-anchored to
`RSpec.describe OdataDuty::OAS2, '<feature>'` (mutant prefix-matches nested subjects such as
`OAS2::CollectionPostPath`). Affected groups live in `create|update|delete/oas2_spec.rb` and
`computed_oas2_spec.rb` in both trees, plus `$oas2` sections inside `search_spec.rb` (both
trees) and `schema_builder_spec.rb` — sections within mixed files move to their own
`OdataDuty::OAS2` describe block in place. Because the current two-tree duplicates are *both*
builder-DSL already, consolidating them into one home (suggested: `spec/odata_duty/oas2/**`)
is recommended; the final layout is the implementer's call.

**Mandatory no-regression verification.** CI's `mutant run --since main` cannot detect
spec-only test-selection changes (no lib code changes → no subjects mutated). `/build` must
therefore run scoped mutant over every constant whose describes change — at minimum
`bundle exec mutant run 'OdataDuty::EntitySet*'` and `'OdataDuty::SchemaBuilder*'` — and show
zero new alive mutations. Any behavior that proves load-bearing for one of those subjects keeps
a small spec under its original describe constant.

## Common error cases

No new errors. `OAS2.build_json` with a class-based `Schema` raises `NoMethodError` today —
documented as unsupported, unchanged. Resolver exceptions raised during `od_after_init`
propagate out of `build_json` as they do today.

## Resolution guide

Per `spec/using_mutant.md`, each survivor is resolved by either an accepted simplification or a
public-API spec. Expected routes per group:

| Group | Subjects | Kill route |
|---|---|---|
| Document skeleton | `OAS2#initialize`, `.build_json`, `#add_error_definition`, `#add_enum_definitions`, `#add_complex_definitions`, `#register_definition` | Full-document pin (schema with title+version, enum, complex, entity types) + targeted no-title/no-version spec + a no-`context:` invocation |
| Capability gating | `#add_collection_paths`, `#add_individual_paths`, `#add_request_body_definitions` | Golden schema mixes full-CRUD and read-only sets; assert present **and absent** operations/definitions |
| Collection POST | 9 `CollectionPostPath` subjects | Exact operation hash + `<EntityType>Create` definition incl. `required` derivation and its omission |
| Individual GET | 3 `IndividualGetPath` subjects | Exact operation hash; both id-type variants |
| Individual PATCH | 10 `IndividualPatchPath` subjects | Exact operation hash + `<EntityType>Update` definition (never `required`) |
| Individual DELETE | 6 `IndividualDeletePath` subjects | Exact operation hash; 204, no `produces` |
| Context plumbing | `#wrap_context` | Full-featured vs. minimal resolver: gated collection parameters appear/disappear |

A small accept/equivalent residue is expected (e.g. `.freeze` removals on constant hashes,
semantics-preserving rewrites). Accept case-by-case; if an acceptance simplifies `lib/` code,
it lands with the specs.

## Scope

**In:**
- Delete all 38 entries from `.mutant.yml`. All 38 subjects finish survivor-free (killed or
  accepted); none stays on the ignore list.
- Re-anchor (and, recommended, consolidate) the `$oas2` example groups; full-document pin plus
  targeted specs.
- The scoped no-regression mutant runs described above.
- Gemspec patch bump iff any `lib/` simplification lands.

**Out:**
- Any change to `$oas2` output values — operationIds, codes, descriptions, definition names all
  stay byte-identical.
- Class-DSL support for `OAS2.build_json`.
- Every other ignore-list entry (e.g. `Property::SingleProp#to_oas2_type`,
  `SchemaBuilder::ComplexType#property`).

## Documentation impact

No new guide; the full-document spec is the reference. Optionally one README line noting
`OAS2.build_json` requires a builder-DSL schema.