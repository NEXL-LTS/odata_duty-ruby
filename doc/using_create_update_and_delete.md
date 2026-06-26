# Using `create`, `update`, and `delete` with OdataDuty

OdataDuty exposes a *writable* entity set the moment your data class (class DSL) or resolver (builder DSL) implements a write method. Three operations are inferred this way:

- Implement `create(input)` and the set accepts `POST` requests, gains a `post` operation in `$oas2`, drops the `InsertRestrictions` annotation in `$metadata`, and advertises an MCP `create_<Set>` tool.
- Implement `update(id, input)` and the set accepts `PATCH` requests against an individual URL, gains a `patch` operation in `$oas2`, drops the `UpdateRestrictions` annotation in `$metadata`, and advertises an MCP `update_<Set>` tool.
- Implement `delete(id)` and the set accepts `DELETE` requests against an individual URL, gains a `delete` operation in `$oas2`, drops the `DeleteRestrictions` annotation in `$metadata`, and advertises an MCP `delete_<Set>` tool.

There is no separate flag or declaration for any of them: availability is inferred from the presence of the method, exactly the way `collection`, `individual`, and `od_search` are inferred. Omit a method and the corresponding capability disappears across all three contracts; omit all three and the set is read-only.

This guide explains how to implement `create`, `update`, and `delete`, and how each choice is reflected in the generated `$oas2`, `$metadata`, and MCP contracts.

## Overview

- **Purpose:** Allow clients to create new records through OData `POST`, modify existing records through OData `PATCH`, and remove existing records through OData `DELETE` (and the equivalent MCP tools).
- **Mechanism:** OdataDuty checks whether your data class / resolver defines `create`, `update`, and / or `delete`. Each method, independently, makes the corresponding operation available; omitting one drops only that capability, and the set is fully read-only only when all three are absent.
- **No new declaration:** Writability is inferred from the method, just like `collection`, `individual`, and `od_search`.
- **Typed input:** `create` and `update` receive a coerced input object built from the request body and mapped onto the entity type's properties. Read fields via `input.property_name`. `update` additionally receives the entity key as its first argument. `delete` receives only the coerced key — a `DELETE` carries no body, so there is no input object.
- **PATCH partial-merge:** `update` uses partial-merge semantics — properties omitted from the request body read as `nil`, so the consumer cannot distinguish "field omitted" from "field explicitly null".
- **Return value:** `create` and `update` return the affected record — the same object shape your entity type's mapper renders for `collection`/`individual`. `delete` returns a truthy value on success and a falsey value to signal "no such record" (which the framework turns into a `ResourceNotFoundError`); on success the response carries no entity payload.
- **Reflected everywhere:** A `create`able set has a `post` in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool. An `update`able set has a `patch` in `$oas2`, no `UpdateRestrictions` annotation in `$metadata`, and an `update_<Set>` MCP tool. A `delete`able set has a `delete` in `$oas2`, no `DeleteRestrictions` annotation in `$metadata`, and a `delete_<Set>` MCP tool. A read-only set has none of these.

## Implementing `create`, `update`, and `delete`

All three operations work the same way in both DSLs:

- `create(input)`: read the coerced fields off `input`, persist a new record, and return it.
- `update(id, input)`: receive the coerced key plus an input object, merge the present fields onto the existing record, and return it. Fields omitted from the request body read as `nil`, so the partial-merge pattern is `... unless input.field.nil?`.
- `delete(id)`: receive the coerced key, remove the record, and return a truthy value. Return a falsey value (e.g. `nil`) when no record matches the key so the framework can raise `ResourceNotFoundError`. A `DELETE` carries no body, so `delete` takes no input object.

### Builder DSL (`OdataDuty::SetResolver`)

A resolver that implements `create`, `update`, and `delete` is writable on all three verbs:

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

  # Receives the coerced key only (DELETE carries no body).
  # Return a truthy value on success; return falsey when no record matches the key.
  def delete(id)
    person = Person.find_by(id: id)
    return nil unless person

    person.destroy!
    true
  end
end
```

A resolver without `create`, `update`, or `delete` is read-only — the data methods are identical, just no write methods:

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

The class DSL behaves identically; the set itself implements `create`, `update`, and `delete`:

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

  # Receives the coerced key only; return truthy on success, falsey if not found.
  def delete(id)
    person = @records.find_by(id: id)
    return nil unless person

    person.destroy!
    person
  end
end
```

Omit `create`, `update`, and `delete` and the same set is read-only:

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

`create` is routed through `schema.create` (POST), `update` through `schema.update` (PATCH), and `delete` through `schema.delete` (DELETE), all mirroring `schema.execute` for GET. `schema.update(url, context:, query_options:)` and `schema.delete(url, context:, query_options:)` are the new public entry points beyond `create`. For `update` the individual URL (e.g. `People('1')`) carries the key while the request body arrives through `query_options`. For `delete` the individual URL carries the key and there is no body; on success `schema.delete` returns no entity payload, so the controller responds `204 No Content`:

```ruby
# config/routes.rb
scope '/api' do
  root 'api#index'
  get '$metadata' => 'api#metadata'
  get '$oas2' => 'api#oas2'
  get '*url' => 'api#show'
  post '*url' => 'api#create'
  patch '*url' => 'api#update'
  delete '*url' => 'api#destroy'
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

def destroy
  schema.delete(params[:url], context: self, query_options: query_options)
  head :no_content
end
```

### How It Works

1. **Discovery:** OdataDuty checks whether your data class / resolver responds to `create`, `update`, and / or `delete`. Each check independently drives the contracts below.
2. **Coercion:** On `POST` the request body is coerced and validated against the entity type's properties into a typed input object passed to `create`. On `PATCH` the key is parsed from the individual URL and coerced to the property-ref's type (the same conversion `individual(id)` receives), and the body is coerced into the same input-object shape passed to `update`. Under partial-merge semantics, properties absent from the body read as `nil`. On `DELETE` the key is parsed from the individual URL and coerced the same way, and passed to `delete` with no body.
3. **Persistence:** Your `create` / `update` persists the record and returns it; your `delete` removes it and returns a truthy value (falsey when no record matches the key).
4. **Rendering:** For `create` / `update` the returned record is run through the entity type's mapper, so the response is the same shape a `GET` would produce, plus the `@odata.context` annotation. For `update` the anchor is the individual `@odata.context` (`.../$metadata#People/$entity`), the same anchor `GET /People('1')` returns. For `delete` there is no entity payload — the controller responds `204 No Content`.

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

A **`delete`able** set's *individual* path gains a `delete` alongside its `get` (and `patch`, if updatable). The `operationId` is `Delete<Set>` (e.g. `DeletePeople`); its only parameter is the `id` path parameter — there is no body. Its responses are `204` No Content (with no success schema) and `default` Error only:

```jsonc
{
  "paths": {
    "/People({id})": {
      "get": { "operationId": "GetIndividualPeopleById" /* ... */ },
      "delete": {
        "operationId": "DeletePeople",
        "parameters": [
          { "name": "id", "in": "path", "required": true, "type": "string" }
        ],
        "responses": {
          "204": { "description": "No Content" },
          "default": { "description": "Unexpected error", "schema": { "$ref": "#/definitions/Error" } }
        }
      }
    }
  }
}
```

A **read-only** set's collection path carries only `get` and its individual path carries only `get` — the `post`, `patch`, and `delete` are omitted entirely:

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

A set **without** `create` carries an `InsertRestrictions` annotation marking it not insertable, a set **without** `update` carries a parallel `UpdateRestrictions` annotation marking it not updatable, and a set **without** `delete` carries a parallel `DeleteRestrictions` annotation marking it not deletable. A set that is none of the three carries all three:

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
    <Annotation Term="Capabilities.DeleteRestrictions">
        <Record>
            <PropertyValue Property="Deletable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```

A set gets no annotation for a capability it supports (the OData defaults are insertable, updatable, and deletable). So a fully writable set with `create`, `update`, and `delete` carries none of the three annotations:

```xml
<EntitySet Name="People" EntityType="MySpace.Person" />
```

The `Org.OData.Capabilities.V1` vocabulary (aliased `Capabilities`) is already referenced at the top of the metadata document, so the annotations need no additional setup.

### MCP

`tools/list` includes a `create_<Set>` tool for each insertable set, an `update_<Set>` tool for each updatable set, and a `delete_<Set>` tool for each deletable set.

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

The `delete_<Set>` tool's `name` is `delete_<Set>`, its `description` is `"Delete an existing <Set> record"`, and its `inputSchema` `properties` contain **only the key** — a `DELETE` carries no body, so no other fields appear. Its `required` array is the key. The key property defaults to computed, so its schema carries `"readOnly": true`:

```jsonc
// tools/list result (deletable People set)
{
  "name": "delete_People",
  "description": "Delete an existing People record",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string", "readOnly": true }
    },
    "required": ["id"]
  }
}
```

A `tools/call` for `create_<Set>` creates the record, a `tools/call` for `update_<Set>` updates it, and a `tools/call` for `delete_<Set>` deletes it, each reusing the same path as the corresponding REST `POST` / `PATCH` / `DELETE`. `create` and `update` return the affected entity as structured JSON; `delete` returns a simple acknowledgement with no entity payload:

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

```jsonc
// tools/call request (delete)
{
  "method": "tools/call",
  "params": {
    "name": "delete_People",
    "arguments": { "id": "1" }
  }
}
```

A read-only set advertises none of these tools, so calling one raises an "Unknown tool" error (see below).

## Common Error Cases

- **`POST` to a set without `create` / `PATCH` to a set without `update` / `DELETE` to a set without `delete`:**
  Raises `OdataDuty::NoImplementationError` with the message `create not implemented for <url>`, `update not implemented for <url>`, or `delete not implemented for <url>` respectively (the set's URL, e.g. `delete not implemented for People`).

- **`PATCH` / `DELETE` for a key that doesn't exist:**
  When your `update` or `delete` cannot find the record and returns a falsey value, the framework raises `OdataDuty::ResourceNotFoundError` (`No such entity <id>`), the same way `individual` does for a missing record.

- **Invalid key in the `PATCH` / `DELETE` URL:**
  A key that can't be coerced to the property-ref's type raises `OdataDuty::InvalidPropertyReferenceValue` (`Invalid individual id : ...`), the same conversion error `individual` produces.

- **Request body that fails coercion/validation:**
  When a body value cannot be coerced to a property's type, the input wrapper rescues the internal `InvalidValue` and raises `OdataDuty::InvalidType` — so `OdataDuty::InvalidType` is what propagates for a wrong-typed value, for both `create` and `update`. Accessing a field that is not a defined property on the input object raises `OdataDuty::NoSuchPropertyError`; unknown keys in the request body are otherwise ignored unless your method accesses them via `input.<that_key>`. (`delete` takes no body, so this case does not apply to it.)

- **MCP `create_<Set>` / `update_<Set>` / `delete_<Set>` for a set that lacks the capability:**
  Because the tool is never listed for such a set, calling it via `tools/call` raises an `"Unknown tool: <tool>"` error rather than `NoImplementationError`.

## Summary

- **Make a set writable** by implementing `create(input)` (insert), `update(id, input)` (partial-merge update), and / or `delete(id)` (remove) on its data class (class DSL) or resolver (builder DSL); omit a method to drop that capability, omit all three to keep the set read-only.
- **`create`** receives a typed, coerced input object and returns the created record. **`update`** additionally receives the coerced key as its first argument; omitted fields read as `nil` (partial merge). Both return the affected record in the same shape `collection`/`individual` return. **`delete`** receives only the coerced key (no body) and returns a truthy value on success or falsey for "no such record" (→ `ResourceNotFoundError`); on success there is no entity payload (`204 No Content`).
- **Insertable** sets gain a `post` (`operationId` `Create<Set>`) on the collection path in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool. **Updatable** sets gain a `patch` (`operationId` `Update<Set>`) on the individual path in `$oas2`, no `UpdateRestrictions` annotation in `$metadata`, and an `update_<Set>` MCP tool (its `inputSchema` includes the key, `required` is the key only). **Deletable** sets gain a `delete` (`operationId` `Delete<Set>`) on the individual path in `$oas2` (responses `204`/`default`, no body), no `DeleteRestrictions` annotation in `$metadata`, and a `delete_<Set>` MCP tool (its `inputSchema`/`required` is the key only). **Read-only** sets lack all of these and carry all three restriction annotations.
