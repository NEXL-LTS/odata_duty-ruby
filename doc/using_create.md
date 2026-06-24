# Using `create` and `update` with OdataDuty

OdataDuty exposes a *writable* entity set the moment your data class (class DSL) or resolver (builder DSL) implements a write method. Two operations are inferred this way:

- Implement `create(input)` and the set accepts `POST` requests, gains a `post` operation in `$oas2`, drops the `InsertRestrictions` annotation in `$metadata`, and advertises an MCP `create_<Set>` tool.
- Implement `update(id, input)` and the set accepts `PATCH` requests against an individual URL, gains a `patch` operation in `$oas2`, drops the `UpdateRestrictions` annotation in `$metadata`, and advertises an MCP `update_<Set>` tool.

There is no separate flag or declaration for either: availability is inferred from the presence of the method, exactly the way `collection`, `individual`, and `od_search` are inferred. Omit a method and the corresponding capability disappears across all three contracts; omit both and the set is read-only.

This guide explains how to implement `create` and `update`, and how each choice is reflected in the generated `$oas2`, `$metadata`, and MCP contracts.

## Overview

- **Purpose:** Allow clients to create new records through OData `POST` and modify existing records through OData `PATCH` (and the equivalent MCP tools).
- **Mechanism:** OdataDuty checks whether your data class / resolver defines `create` and / or `update`. Each method, independently, makes the corresponding operation available; absence keeps it read-only.
- **No new declaration:** Writability is inferred from the method, just like `collection`, `individual`, and `od_search`.
- **Typed input:** Both methods receive a coerced input object built from the request body and mapped onto the entity type's properties. Read fields via `input.property_name`. `update` additionally receives the entity key as its first argument.
- **PATCH partial-merge:** `update` uses partial-merge semantics — properties omitted from the request body read as `nil`, so the consumer cannot distinguish "field omitted" from "field explicitly null".
- **Return value:** Both methods return the affected record — the same object shape your entity type's mapper renders for `collection`/`individual`.
- **Reflected everywhere:** A `create`able set has a `post` in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool. An `update`able set has a `patch` in `$oas2`, no `UpdateRestrictions` annotation in `$metadata`, and an `update_<Set>` MCP tool. A read-only set has none of these.

## Implementing `create` and `update`

Both DSLs work the same way:

- `create(input)`: read the coerced fields off `input`, persist a new record, and return it.
- `update(id, input)`: receive the coerced key plus an input object, merge the present fields onto the existing record, and return it. Fields omitted from the request body read as `nil`, so the partial-merge pattern is `... unless input.field.nil?`.

### Builder DSL (`OdataDuty::SetResolver`)

A resolver that implements `create` and `update` is writable on both verbs:

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

  # Receives a typed, coerced input object. Access fields via input.property_name.
  # Returns the created record (same shape collection/individual return).
  def create(input)
    Person.create!(user_name: input.user_name, name: input.name, emails: input.emails)
  end

  # Receives the coerced key and a typed input object (omitted fields read as nil).
  # Returns the updated record (same shape collection/individual return).
  def update(id, input)
    person = Person.find(id)
    person.update!(name: input.name) unless input.name.nil?
    person
  end
end
```

A resolver without `create` or `update` is read-only — the data methods are identical, just no write methods:

```ruby
class CountriesResolver < OdataDuty::SetResolver
  def od_after_init
    @records = Country.all
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end
```

### Class DSL (`OdataDuty::EntitySet`)

The class DSL behaves identically; the set itself implements `create` and `update`:

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

  # Receives a typed, coerced input object. Access fields via input.property_name.
  def create(input)
    Person.create!(user_name: input.user_name, name: input.name, emails: input.emails)
  end

  # Receives the coerced key and a typed input object (omitted fields read as nil).
  def update(id, input)
    person = @records.find(id)
    person.update!(name: input.name) unless input.name.nil?
    person.update!(emails: input.emails) unless input.emails.nil?
    person
  end
end
```

Omit `create` and `update` and the same set is read-only:

```ruby
class CountriesSet < OdataDuty::EntitySet
  entity_type CountryEntity

  def od_after_init
    @records = Country.all
  end

  def collection
    @records
  end

  def individual(id)
    @records.find(id)
  end
end
```

### Invoking it (Rails controller wiring)

`create` is routed through `schema.create` (POST) and `update` through `schema.update` (PATCH), mirroring `schema.execute` for GET. `schema.update(url, context:, query_options:)` is the only new public entry point beyond `create`; the individual URL (e.g. `People('1')`) carries the key, while the request body arrives through `query_options` — the same channel `create` uses for its body:

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
def create
  render json: schema.create(params[:url], context: self, query_options: query_options)
end

def update
  render json: schema.update(params[:url], context: self, query_options: query_options)
end
```

### How It Works

1. **Discovery:** OdataDuty checks whether your data class / resolver responds to `create` and / or `update`. Each check independently drives the contracts below.
2. **Coercion:** On `POST` the request body is coerced and validated against the entity type's properties into a typed input object passed to `create`. On `PATCH` the key is parsed from the individual URL and coerced to the property-ref's type (the same conversion `individual(id)` receives), and the body is coerced into the same input-object shape passed to `update`. Under partial-merge semantics, properties absent from the body read as `nil`.
3. **Persistence:** Your `create` / `update` persists the record and returns it.
4. **Rendering:** The returned record is run through the entity type's mapper, so the response is the same shape a `GET` would produce, plus the `@odata.context` annotation. For `update` the anchor is the individual `@odata.context` (`.../$metadata#People/$entity`), the same anchor `GET /People('1')` returns.

### Example `PATCH` request / response

A `PATCH` to an individual URL applies a partial merge:

```http
PATCH /api/People('1')
Content-Type: application/json

{ "name": "Alice Updated" }
```

Response (the updated entity, mapper-rendered, with the individual `@odata.context` anchor):

```jsonc
{
  "@odata.context": "https://host/api/$metadata#People/$entity",
  "id": "1",
  "user_name": "alice",
  "name": "Alice Updated",
  "emails": ["alice@example.com"]
}
```

Because semantics are partial-merge, fields omitted from the body (`user_name`, `emails` above) read as `nil` inside `update`, and the example consumer leaves them untouched.

## Reflected in the generated contracts

### `$oas2`

A **`create`able** set's collection path exposes both `get` and `post`. The `post` operation's `operationId` is `Create<Set>` (e.g. `CreatePeople`):

```jsonc
{
  "paths": {
    "/People": {
      "get": { "operationId": "ListPeople" /* ... */ },
      "post": {
        "operationId": "CreatePeople",
        "produces": ["application/json"],
        "parameters": [
          { "name": "body", "in": "body", "required": true,
            "schema": { "$ref": "#/definitions/Person" } }
        ],
        "responses": {
          "200": { "description": "Success", "schema": { "$ref": "#/definitions/Person" } },
          "201": { "description": "Created", "schema": { "$ref": "#/definitions/Person" } },
          "default": { "description": "Unexpected error", "schema": { "$ref": "#/definitions/Error" } }
        }
      }
    }
  }
}
```

An **`update`able** set's *individual* path gains a `patch` alongside its `get`. The `operationId` is `Update<Set>` (e.g. `UpdatePeople`); its parameters are the `id` path parameter plus a required `body` parameter `$ref`ing the entity. Note the responses are `200` Success and `default` Error only — there is no `201`, unlike `create`'s `post`:

```jsonc
{
  "paths": {
    "/People({id})": {
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

A **read-only** set's collection path carries only `get` and its individual path carries only `get` — the `post` and `patch` are omitted entirely:

```jsonc
{
  "paths": {
    "/Countries": {
      "get": { "operationId": "ListCountries" /* ... */ }
    },
    "/Countries({id})": {
      "get": { "operationId": "GetIndividualCountriesById" /* ... */ }
    }
  }
}
```

### `$metadata` (EDMX)

A set **without** `create` carries an `InsertRestrictions` annotation marking it not insertable, and a set **without** `update` carries a parallel `UpdateRestrictions` annotation marking it not updatable. A set that is neither insertable nor updatable carries both:

```xml
<EntitySet Name="Countries" EntityType="MySpace.Country">
    <Annotation Term="Capabilities.InsertRestrictions">
        <Record>
            <PropertyValue Property="Insertable" Bool="false" />
        </Record>
    </Annotation>
    <Annotation Term="Capabilities.UpdateRestrictions">
        <Record>
            <PropertyValue Property="Updatable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```

A set gets no annotation for a capability it supports (the OData defaults are insertable and updatable). So a set with both `create` and `update` carries neither annotation:

```xml
<EntitySet Name="People" EntityType="MySpace.Person" />
```

The `Org.OData.Capabilities.V1` vocabulary (aliased `Capabilities`) is already referenced at the top of the metadata document, so the annotations need no additional setup.

### MCP

`tools/list` includes a `create_<Set>` tool for each insertable set and an `update_<Set>` tool for each updatable set.

The `create_<Set>` tool's `name` is `create_<Set>`, its `description` is `"Create a new <Set> record"`, and its `inputSchema` is an object whose `properties` are the entity type's writable properties and whose `required` array is the non-nullable property names:

```jsonc
// tools/list result (insertable People set)
{
  "name": "create_People",
  "description": "Create a new People record",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string" /* ... */ },
      "user_name": { "type": "string" /* ... */ },
      "name": { "type": "string" /* ... */ },
      "emails": { "type": "array" /* ... */ }
    },
    "required": ["id", "user_name", "emails"]
  }
}
```

The `update_<Set>` tool's `name` is `update_<Set>`, its `description` is `"Update an existing <Set> record"`, and its `inputSchema` `properties` are the **key property plus the writable properties**. Its `required` array contains **only the key** — the key locates the record, while every other field is optional under partial-merge semantics. The key property defaults to computed, so its schema carries `"readOnly": true`:

```jsonc
// tools/list result (updatable People set)
{
  "name": "update_People",
  "description": "Update an existing People record",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string", "readOnly": true /* ... */ },
      "user_name": { "type": "string" /* ... */ },
      "name": { "type": "string" /* ... */ },
      "emails": { "type": "array" /* ... */ }
    },
    "required": ["id"]
  }
}
```

A `tools/call` for `create_<Set>` creates the record and a `tools/call` for `update_<Set>` updates it; each returns the affected entity as structured JSON, reusing the same path as the REST `POST` / `PATCH`:

```jsonc
// tools/call request (update)
{
  "method": "tools/call",
  "params": {
    "name": "update_People",
    "arguments": { "id": "1", "name": "Alice Updated" }
  }
}
```

A read-only set advertises neither tool, so calling one raises an "Unknown tool" error (see below).

## Common Error Cases

- **`POST` to a set without `create` / `PATCH` to a set without `update`:**
  Raises `OdataDuty::NoImplementationError` with the message `create not implemented for <url>` or `update not implemented for <url>` respectively (the set's URL, e.g. `update not implemented for People`).

- **`PATCH` for a key that doesn't exist:**
  When your `update` cannot find the record and returns a falsey value, the framework raises `OdataDuty::ResourceNotFoundError` (`No such entity <id>`), the same way `individual` does for a missing record.

- **Invalid key in the `PATCH` URL:**
  A key that can't be coerced to the property-ref's type raises `OdataDuty::InvalidPropertyReferenceValue` (`Invalid individual id : ...`), the same conversion error `individual` produces.

- **Request body that fails coercion/validation:**
  When a body value cannot be coerced to a property's type, the input wrapper rescues the internal `InvalidValue` and raises `OdataDuty::InvalidType` — so `OdataDuty::InvalidType` is what propagates for a wrong-typed value, for both `create` and `update`. Accessing a field that is not a defined property on the input object raises `OdataDuty::NoSuchPropertyError`; unknown keys in the request body are otherwise ignored unless your method accesses them via `input.<that_key>`.

- **MCP `create_<Set>` / `update_<Set>` for a set that lacks the capability:**
  Because the tool is never listed for such a set, calling it via `tools/call` raises an `"Unknown tool: <tool>"` error rather than `NoImplementationError`.

## Summary

- **Make a set writable** by implementing `create(input)` (insert) and / or `update(id, input)` (partial-merge update) on its data class (class DSL) or resolver (builder DSL); omit a method to drop that capability, omit both to keep the set read-only.
- **`create`** receives a typed, coerced input object and returns the created record. **`update`** additionally receives the coerced key as its first argument; omitted fields read as `nil` (partial merge). Both return the affected record in the same shape `collection`/`individual` return.
- **Insertable** sets gain a `post` (`operationId` `Create<Set>`) on the collection path in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool. **Updatable** sets gain a `patch` (`operationId` `Update<Set>`) on the individual path in `$oas2`, no `UpdateRestrictions` annotation in `$metadata`, and an `update_<Set>` MCP tool (its `inputSchema` includes the key, `required` is the key only). **Read-only** sets lack all of these and carry both restriction annotations.
