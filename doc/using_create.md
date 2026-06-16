# Using `create` with OdataDuty

OdataDuty exposes a *writable* entity set the moment your data class (class DSL) or resolver (builder DSL) implements a `create` method. There is no separate flag or declaration to set: availability is inferred from the presence of `create`, exactly the way `collection`, `individual`, and `od_search` are inferred. Implement `create` and the set accepts `POST` requests, gains a `post` operation in `$oas2`, drops the read-only annotation in `$metadata`, and advertises an MCP `create_<Set>` tool. Omit it and the set is read-only across all three contracts.

This guide explains how to implement `create` and how the choice is reflected in the generated `$oas2`, `$metadata`, and MCP contracts.

## Overview

- **Purpose:** Allow clients to create new records through OData `POST` (and the equivalent MCP tool).
- **Mechanism:** OdataDuty checks whether your data class / resolver defines `create`. If it does, the set is writable; if not, it is read-only.
- **No new declaration:** Writability is inferred from the method, just like `collection`, `individual`, and `od_search`.
- **Typed input:** `create` receives a coerced input object built from the request body and mapped onto the entity type's properties. Read fields via `input.property_name`.
- **Return value:** `create` returns the created record — the same object shape your entity type's mapper renders for `collection`/`individual`.
- **Reflected everywhere:** A writable set has a `post` in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool. A read-only set has none of these.

## Implementing `create`

Both DSLs work the same way: define `create(input)`, read the coerced fields off `input`, persist the record, and return it.

### Builder DSL (`OdataDuty::SetResolver`)

A resolver that implements `create` is writable:

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
end
```

A resolver without `create` is read-only — the data methods are identical, just no `create`:

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

The class DSL behaves identically; the set itself implements `create`:

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
end
```

Omit `create` and the same set is read-only:

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

### How It Works

1. **Discovery:** OdataDuty checks whether your data class / resolver responds to `create`. That single check drives every contract below.
2. **Coercion:** On `POST`, the request body is coerced and validated against the entity type's properties into a typed input object, which is passed to your `create`.
3. **Persistence:** Your `create` persists the record and returns it.
4. **Rendering:** The returned record is run through the entity type's mapper, so the response is the same shape a `GET` would produce, plus the `@odata.context` annotation.

## Reflected in the generated contracts

### `$oas2`

A **writable** set's collection path exposes both `get` and `post`. The `post` operation's `operationId` is `Create<Set>` (e.g. `CreatePeople`):

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

A **read-only** set's path carries only `get` — the `post` is omitted entirely:

```jsonc
{
  "paths": {
    "/Countries": {
      "get": { "operationId": "ListCountries" /* ... */ }
    }
  }
}
```

### `$metadata` (EDMX)

A **read-only** set's `<EntitySet>` carries an `InsertRestrictions` annotation marking it not insertable:

```xml
<EntitySet Name="Countries" EntityType="MySpace.Country">
    <Annotation Term="Capabilities.InsertRestrictions">
        <Record>
            <PropertyValue Property="Insertable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```

A **writable** set gets no such annotation (the OData default is insertable):

```xml
<EntitySet Name="People" EntityType="MySpace.Person" />
```

The `Org.OData.Capabilities.V1` vocabulary (aliased `Capabilities`) is already referenced at the top of the metadata document, so the annotation needs no additional setup.

### MCP

`tools/list` includes a `create_<Set>` tool for each writable set. The tool's `name` is `create_<Set>`, its `description` is `"Create a new <Set> record"`, and its `inputSchema` is an object whose `properties` are the entity type's properties and whose `required` array is the non-nullable property names:

```jsonc
// tools/list result (writable People set)
{
  "tools": [
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
  ]
}
```

A `tools/call` for `create_<Set>` creates the record and returns the created entity as structured JSON, reusing the same create path as the REST `POST`:

```jsonc
// tools/call request
{
  "method": "tools/call",
  "params": {
    "name": "create_People",
    "arguments": { "user_name": "alice", "name": "Alice", "emails": ["alice@example.com"] }
  }
}
```

A read-only set advertises no `create_<Set>` tool, so calling one raises an "Unknown tool" error (see below).

## Common Error Cases

- **`POST` to a set without `create`:**
  A `POST` to a read-only set raises `OdataDuty::NoImplementationError` with the message `create not implemented for <url>` (the set's URL, e.g. `create not implemented for People`).

- **MCP `create_<Set>` for a read-only set:**
  Because the tool is never listed for a read-only set, calling it via `tools/call` raises an `"Unknown tool: create_<Set>"` error rather than `NoImplementationError`.

- **Request body that fails coercion/validation:**
  When a body value cannot be coerced to a property's type, the input wrapper (`CreateComplexTypeHashWrapper`) rescues the internal `InvalidValue` and raises `OdataDuty::InvalidType` — so `OdataDuty::InvalidType` is what propagates for a wrong-typed value. Accessing a field that is not a defined property on the input object raises `OdataDuty::NoSuchPropertyError`; unknown keys in the request body are otherwise ignored unless your `create` accesses them via `input.<that_key>`.

## Summary

- **Make a set writable** by implementing `create(input)` on its data class (class DSL) or resolver (builder DSL); omit it to keep the set read-only.
- **`create`** receives a typed, coerced input object (read fields via `input.property_name`) and returns the created record in the same shape `collection`/`individual` return.
- **Writable** sets gain a `post` (`operationId` `Create<Set>`) in `$oas2`, no `InsertRestrictions` annotation in `$metadata`, and a `create_<Set>` MCP tool — all of which **read-only** sets lack.
