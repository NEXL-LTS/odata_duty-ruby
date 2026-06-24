# PRD: Update support (`update` hook / OData `PATCH`)

## Summary

Let a gem consumer make an entity set *updatable* by implementing a single `update(id, input)`
method on its data class (class DSL) or resolver (builder DSL). Implementing it makes the set
accept OData `PATCH` requests against an individual URL, adds a `patch` operation to `$oas2`,
drops the read-only update annotation in `$metadata`, and advertises an `update_<Set>` MCP tool —
exactly mirroring how `create` makes a set insertable today.

## Goal / Problem

OdataDuty already lets a consumer expose reads (`collection`, `individual`, `count`) and inserts
(`create`). There is no consumer-facing way to expose *updates*. A consumer who wants clients
(PowerBI, PowerAutomate, an LLM via MCP) to modify an existing record has to fall outside the
gem entirely. This PRD closes that gap with the same "implement a method, availability is
inferred" ergonomics the gem already uses for every other operation.

## What it enables

- As a gem consumer, I can implement `update(id, input)` on a data class / resolver and my set
  starts accepting OData `PATCH` requests to an individual URL (e.g. `PATCH /People('1')`).
- As a gem consumer, I get a `patch` operation in the generated `$oas2` for that set's individual
  path, with no extra declaration.
- As a gem consumer, my updatable set is **not** annotated read-only-for-update in `$metadata`,
  while sets without `update` carry an `UpdateRestrictions / Updatable=false` annotation.
- As an MCP client (or LLM), I can call an `update_<Set>` tool that reuses the same update path
  as the REST `PATCH`.
- As a gem consumer, I do nothing extra to keep a set read-only: omit `update` and none of the
  above appears, across all three contracts.

**Scope limits (this PRD):**

- **PATCH (partial merge) semantics only.** No `PUT` / full-replace verb.
- The input object exposes **all** writable properties; properties omitted from the request body
  read as `nil`. This means the consumer **cannot** distinguish "field omitted" from "field
  explicitly set to null" — see Common Error Cases / Open Questions.

## External API

Availability is **inferred from the presence of `update`**, identical to how `create`,
`collection`, `individual`, and `od_search` are inferred. No new declaration or flag.

### The `update` hook contract

- **Signature:** `update(id, input)`.
- **`id`** — the entity key, already coerced to the property-ref's type (the same conversion
  `individual(id)` receives). For an integer key you get an `Integer`; for a string key, a
  `String`.
- **`input`** — a typed, coerced input object built from the `PATCH` request body and mapped onto
  the entity type's properties, the same object shape `create` receives. Read fields via
  `input.property_name`. Properties not present in the request body read as `nil`.
- **Return value:** the updated record — the same object shape your entity type's mapper renders
  for `collection` / `individual`. The framework runs it through the mapper, so the response is
  the same shape a `GET` of that individual would produce, plus the `@odata.context` annotation.
- **When called:** on a `PATCH` to an individual URL of an updatable set, after the id is parsed
  from the URL and the body is coerced.

### Class DSL (`OdataDuty::EntitySet`)

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = Person.active
  end

  def collection
    @records
  end

  def individual(id)
    @records.find(id)
  end

  def create(input)
    Person.create!(user_name: input.user_name, name: input.name, emails: input.emails)
  end

  # Receives the coerced key and a typed input object (omitted fields read as nil).
  # Returns the updated record (same shape collection/individual return).
  def update(id, input)
    person = @records.find(id)
    person.update!(name: input.name) unless input.name.nil?
    person.update!(emails: input.emails) unless input.emails.nil?
    person
  end
end
```

Omit `update` and the same set is not updatable — no `patch`, an `UpdateRestrictions` annotation,
and no MCP `update_<Set>` tool.

### Builder DSL (`OdataDuty::SetResolver`)

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = Person.all
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end

  # Same contract as the class DSL.
  def update(id, input)
    person = Person.find(id)
    person.update!(name: input.name) unless input.name.nil?
    person
  end
end
```

### Invoking it (Rails controller wiring)

The consumer routes `PATCH` to a new `schema.update`, mirroring `schema.execute` (GET) and
`schema.create` (POST):

```ruby
# config/routes.rb
scope '/api' do
  root 'api#index'
  get '$metadata' => 'api#metadata'
  get '$oas2' => 'api#oas2'
  get '*url' => 'api#show'
  post '*url' => 'api#create'
  patch '*url' => 'api#update'
end
```

```ruby
# app/controllers/api_controller.rb
def update
  render json: schema.update(params[:url], context: self, query_options: query_options)
end
```

`schema.update(url, context:, query_options:)` is the only new public entry point on `Schema`.
The individual URL (e.g. `People('1')`) carries the key; the request body arrives through
`query_options`, the same channel `create` uses for its body.

## Behavior & expected I/O

### REST `PATCH`

Request:

```http
PATCH /api/People('1')
Content-Type: application/json

{ "name": "Alice Updated" }
```

Response (the updated entity, mapper-rendered, with the individual `@odata.context` anchor —
the same anchor `GET /People('1')` returns):

```jsonc
{
  "@odata.context": "https://host/api/$metadata#People/$entity",
  "id": "1",
  "user_name": "alice",
  "name": "Alice Updated",
  "emails": ["alice@example.com"]
}
```

Because semantics are partial-merge, fields omitted from the body (`user_name`, `emails` above)
read as `nil` inside `update`, and the example consumer leaves them untouched.

### `$oas2`

An **updatable** set's individual path gains a `patch` alongside the existing `get`. The
`operationId` is `Update<Set>` (e.g. `UpdatePeople`); the body `$ref` and success `schema` both
point at the entity definition, matching the `create` `post` convention:

```jsonc
{
  "paths": {
    "/People('{id}')": {
      "get": { "operationId": "GetIndividualPeopleById" /* ... */ },
      "patch": {
        "operationId": "UpdatePeople",
        "produces": ["application/json"],
        "parameters": [
          { "name": "id", "in": "path", "required": true, "type": "string" },
          { "name": "body", "in": "body", "required": true,
            "schema": { "$ref": "#/definitions/Person" } }
        ],
        "responses": {
          "200": { "description": "Success", "schema": { "$ref": "#/definitions/Person" } },
          "default": { "description": "Unexpected error", "schema": { "$ref": "#/definitions/Error" } }
        }
      }
    }
  }
}
```

A set without `update` exposes only `get` on its individual path — the `patch` is omitted
entirely. (The exact individual-path key encoding follows whatever `$oas2` already emits for the
`get` individual path; `update` adds the `patch` to that same path object.)

### `$metadata` (EDMX)

A set **without** `update` carries a `Capabilities.UpdateRestrictions` annotation marking it not
updatable, paralleling the existing `InsertRestrictions` annotation for non-insertable sets:

```xml
<EntitySet Name="Countries" EntityType="MySpace.Country">
    <Annotation Term="Capabilities.UpdateRestrictions">
        <Record>
            <PropertyValue Property="Updatable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```

An **updatable** set gets no such annotation (the OData default is updatable). A set that is
neither insertable nor updatable carries both annotations. The `Org.OData.Capabilities.V1`
vocabulary (aliased `Capabilities`) is already referenced at the top of the metadata document, so
the annotation needs no additional setup.

### MCP

`tools/list` includes an `update_<Set>` tool for each updatable set, mirroring `create_<Set>`:

- **`name`:** `update_<Set>` (e.g. `update_People`).
- **`description`:** `"Update an existing <Set> record"`.
- **`inputSchema`:** an object whose `properties` are the entity type's writable properties (the
  same set `create_<Set>` exposes), and whose `required` array contains **only the key property**
  — the key is needed to locate the record, while every other field is optional under
  partial-merge semantics.

```jsonc
// tools/list result (updatable People set)
{
  "tools": [
    {
      "name": "update_People",
      "description": "Update an existing People record",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id": { "type": "string" /* ... */ },
          "user_name": { "type": "string" /* ... */ },
          "name": { "type": "string" /* ... */ },
          "emails": { "type": "array" /* ... */ }
        },
        "required": ["id"]
      }
    }
  ]
}
```

A `tools/call` for `update_<Set>` updates the record and returns the updated entity as structured
JSON, reusing the same update path as the REST `PATCH`:

```jsonc
// tools/call request
{
  "method": "tools/call",
  "params": {
    "name": "update_People",
    "arguments": { "id": "1", "name": "Alice Updated" }
  }
}
```

A set without `update` advertises no `update_<Set>` tool, so calling one raises an "Unknown tool"
error.

## Common error cases

- **`PATCH` to a set without `update`:** raises `OdataDuty::NoImplementationError` with the
  message `update not implemented for <url>` (the set's URL, e.g. `update not implemented for
  People`) — mirroring `create not implemented for <url>`.
- **`PATCH` for a key that doesn't exist:** when the consumer's `update` cannot find the record
  and returns a falsey value, the framework raises `OdataDuty::ResourceNotFoundError`
  (`No such entity <id>`), the same way `individual` does for a missing record.
- **Invalid key in the URL:** a key that can't be coerced to the property-ref's type raises
  `OdataDuty::InvalidPropertyReferenceValue` (`Invalid individual id : ...`), the same conversion
  error `individual` produces.
- **Request body that fails coercion/validation:** a body value that cannot be coerced to a
  property's type raises `OdataDuty::InvalidType` (`The value provided for '<field>' is of wrong
  type`). Accessing a field that is not a defined property raises
  `OdataDuty::NoSuchPropertyError`; unknown keys in the body are ignored unless the consumer reads
  them via `input.<that_key>`. Identical to `create`'s input handling.
- **MCP `update_<Set>` for a non-updatable set:** because the tool is never listed, calling it via
  `tools/call` raises an `"Unknown tool: update_<Set>"` error rather than
  `NoImplementationError`.

## Scope

**In:**

- `update(id, input)` hook on both the class DSL (`OdataDuty::EntitySet`) and the builder DSL
  (`OdataDuty::SetResolver`).
- `Schema.update(url, context:, query_options:)` public entry point for routing `PATCH`.
- OData `PATCH` (partial merge) against an individual URL.
- Reflection across `$oas2` (`patch` on the individual path), `$metadata`
  (`UpdateRestrictions` for non-updatable sets), and MCP (`update_<Set>` tool).

**Out:**

- `PUT` / full-replace semantics.
- Distinguishing "field omitted" from "field explicitly null" (omitted fields read as `nil`).
- `DELETE` support, upsert, and bulk/batch updates.
- Concurrency / `If-Match` / ETag handling.

**DSLs covered:** both class-based and builder, with matching spec coverage under
`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`.

## Documentation impact

Fold `create` and `update` into a single **write-operations guide** — evolve
**`doc/using_create.md`** (e.g. into a "Using `create` and `update`" / write-operations guide)
rather than adding a separate `doc/using_update.md`, keeping the same purpose-first,
example-driven style (Overview → Implementing in both DSLs → How it works → Reflected in
`$oas2` / `$metadata` / MCP → Common Error Cases), with `update` presented alongside `create`
throughout. Update the README's *Further Documentation* link to point at the combined guide. Do
not write the guide as part of this PRD.