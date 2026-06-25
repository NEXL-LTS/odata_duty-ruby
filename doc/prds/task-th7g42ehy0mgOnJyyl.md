# PRD: `delete` support

## Summary

Add a third write operation, `delete`, to OdataDuty. A gem consumer makes an entity set
deletable by implementing a `delete(id)` method on its data class (class DSL) or resolver
(builder DSL); the set then accepts OData `DELETE` requests against an individual URL and gains
the matching `delete` operation in `$oas2`, drops the `DeleteRestrictions` annotation in
`$metadata`, and advertises a `delete_<Set>` MCP tool. This completes the create / update /
delete trio for record-level writes.

## Goal / Problem

Today OdataDuty can insert (`create`) and partially update (`update`) records, but there is no
way to remove one. A consumer modelling a writable resource has to expose deletion out-of-band
(a custom Rails route, a side channel), which breaks the "define once, serve everywhere"
promise: the deletion capability is invisible to `$oas2`, `$metadata`, and MCP clients, so
analytics tools, no-code platforms, and agents can't discover or invoke it.

`delete` closes that gap by following the exact same inference model as `create` and `update`:
the capability appears the moment the method exists and disappears the moment it doesn't, with
no separate flag or declaration.

## What it enables

- As a gem consumer, I can make an entity set deletable by implementing `delete(id)` — no new
  declaration, just the method, exactly like `create` and `update`.
- As a gem consumer, I can keep a set non-deletable simply by not implementing `delete`; the set
  then carries a `DeleteRestrictions` annotation marking it not deletable, and `DELETE` requests
  raise `NoImplementationError`.
- As an OData / OpenAPI client, I can discover a `delete` operation on the individual path and
  issue `DELETE /People('1')`, receiving `204 No Content` on success.
- As an MCP client / agent, I can discover and call a `delete_<Set>` tool that takes only the
  record key.

**Scope limits:** `delete` operates on a single record addressed by its key (an individual URL).
Bulk / filtered deletes (`DELETE /People?$filter=...`), soft-delete semantics, and composite
keys are out of scope (composite keys are unsupported across the gem generally). `delete` takes
no request body.

## External API

`delete` is inferred from the presence of the method, identically to `create`/`update`. It
receives the coerced entity key (the same value `individual(id)` and `update(id, …)` receive as
their first argument) and takes **no input object**, because `DELETE` carries no body.

**Return contract:** `delete(id)` must return a truthy value on success. Returning a falsey
value signals "no such record" and makes the framework raise `ResourceNotFoundError` — the same
convention `update` uses for a missing key.

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

  # Receives the coerced key. Returns a truthy value on success;
  # return falsey (e.g. nil) when no record matched -> ResourceNotFoundError.
  def delete(id)
    person = @records.find_by(id: id)
    return nil unless person

    person.destroy!
    person
  end
end
```

Omit `delete` and the same set is not deletable.

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

  # Receives the coerced key. Truthy on success; falsey -> ResourceNotFoundError.
  def delete(id)
    person = Person.find_by(id: id)
    return nil unless person

    person.destroy!
    true
  end
end
```

### Invoking it (Rails controller wiring)

`delete` is routed through a new public entry point `schema.delete(url, context:, query_options:)`,
mirroring `schema.execute` (GET), `schema.create` (POST), and `schema.update` (PATCH). The
individual URL (e.g. `People('1')`) carries the key; there is no body. On success the controller
should respond `204 No Content`:

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
def destroy
  schema.delete(params[:url], context: self, query_options: query_options)
  head :no_content
end
```

### Rails generator impact

The capability must also surface in the Rails generators, so a consumer who scaffolds an API gets
deletion wired up (or at least scaffolded) rather than having to hand-add it.

**`odata_duty:install` generator** — the generated controller and routes gain the `DELETE` verb,
mirroring the controller wiring above:

- `controller.rb.tt` gains a `destroy` action that calls `schema.delete(...)` and responds
  `head :no_content`.
- `install_generator.rb`'s `route_contents` adds `delete '*url' => '<controller>#destroy'` to the
  generated `scope '/api'` block.

```ruby
# generated app/controllers/.../api_controller.rb (new action)
def destroy
  schema.delete(params[:url], context: self, query_options: query_options)
  head :no_content
end
```

```ruby
# generated routes (new line in the scope block)
delete '*url' => 'api#destroy'
```

**`odata_duty:entity_set` generator** — the scaffolded set / resolver gains a `delete(id)` method,
scaffolded the same way `create` is today (i.e. an optional, ready-to-edit method):

- `resolver.rb.erb` (builder DSL) gains a `delete(id)` method alongside its optional `create`.
- `entity_set.rb.erb` (class DSL) gains a `delete(id)` method alongside its `create`.
- The generated specs (`resolver_spec.rb.erb`, `entity_set_spec.rb.erb`) gain a `#delete` example
  covering the success and not-found (`ResourceNotFoundError`) paths.

```ruby
# generated resolver.rb.erb (new method)
# Optional: Implement delete method to support DELETE operations
def delete(id)
  # Find and remove the entity by id; return truthy on success, falsey if not found
  <%= file_name %> = @<%= file_name.pluralize %>.find { |item| item.<%= attributes.first.name %> == id }
  return nil unless <%= file_name %>

  @<%= file_name.pluralize %>.delete(<%= file_name %>)
  <%= file_name %>
end
```

> **Pre-existing gap to confirm:** The install generator's controller and routes currently emit
> only `get`/`post` (no `patch`/`update`), and the entity-set templates scaffold only `create` — so
> the generators already lag the shipped `update` feature. This PRD scopes the generator work to
> `delete`, but the same edit could bring `update` (`patch` route + `update` controller action +
> scaffolded `update(id, input)`) up to date at the same time. See Open Questions.

## Behavior & expected I/O

### Successful `DELETE`

```http
DELETE /api/People('1')
```

Response — no body:

```http
HTTP/1.1 204 No Content
```

`schema.delete` returns no entity payload (unlike `create`/`update`, which return the
mapper-rendered record). The framework only validates the key, dispatches to `delete(id)`, and
confirms a truthy result; the controller emits `204`.

### `$oas2`

A **deletable** set's *individual* path gains a `delete` alongside its `get` (and `patch` if
updatable). The `operationId` is `Delete<Set>` (e.g. `DeletePeople`); its only parameter is the
`id` path parameter — there is no `body` parameter, since `DELETE` carries no request body. The
success response is `204 No Content` with no schema, plus the standard `default` Error:

```jsonc
{
  "paths": {
    "/People({id})": {
      "get": { "operationId": "GetIndividualPeopleById" /* ... */ },
      "patch": { "operationId": "UpdatePeople" /* ... */ },
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

A **non-deletable** set's individual path carries only `get` (and `patch` if updatable) — the
`delete` is omitted entirely:

```jsonc
{
  "paths": {
    "/Countries({id})": {
      "get": { "operationId": "GetIndividualCountriesById" /* ... */ }
    }
  }
}
```

### `$metadata` (EDMX)

A set **without** `delete` carries a `DeleteRestrictions` annotation marking it not deletable,
parallel to the existing `InsertRestrictions` / `UpdateRestrictions` annotations. A set that
supports `delete` gets **no** annotation (the OData default is deletable):

```xml
<EntitySet Name="Countries" EntityType="MySpace.Country">
    <Annotation Term="Capabilities.DeleteRestrictions">
        <Record>
            <PropertyValue Property="Deletable" Bool="false" />
        </Record>
    </Annotation>
</EntitySet>
```

A fully writable set (`create` + `update` + `delete`) carries none of the three restriction
annotations:

```xml
<EntitySet Name="People" EntityType="MySpace.Person" />
```

The `Org.OData.Capabilities.V1` vocabulary (aliased `Capabilities`) is already referenced at the
top of the metadata document, so the annotation needs no additional setup.

### MCP

`tools/list` includes a `delete_<Set>` tool for each deletable set. Its `name` is `delete_<Set>`,
its `description` is `"Delete an existing <Set> record"`, and its `inputSchema` is an object whose
`properties` contain **only the key property** and whose `required` array contains **only the
key** — deletion needs nothing but the key to locate the record. The key property defaults to
computed, so its schema carries `"readOnly": true`:

```jsonc
// tools/list result (deletable People set)
{
  "name": "delete_People",
  "description": "Delete an existing People record",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string", "readOnly": true /* ... */ }
    },
    "required": ["id"]
  }
}
```

A `tools/call` for `delete_<Set>` deletes the record, reusing the same path as the REST `DELETE`:

```jsonc
// tools/call request
{
  "method": "tools/call",
  "params": {
    "name": "delete_People",
    "arguments": { "id": "1" }
  }
}
```

On success the tool returns a simple acknowledgement of the deletion (no entity payload), mirroring
the `204 No Content` REST response. A non-deletable set advertises no such tool, so calling it via
`tools/call` raises an `"Unknown tool: <tool>"` error.

## Common error cases

- **`DELETE` to a set without `delete`:** Raises `OdataDuty::NoImplementationError` with the
  message `delete not implemented for <url>` (the set's URL, e.g. `delete not implemented for
  People`), mirroring `create`/`update`.

- **`DELETE` for a key that doesn't exist:** When your `delete` cannot find the record and
  returns a falsey value, the framework raises `OdataDuty::ResourceNotFoundError`
  (`No such entity <id>`), the same way `individual` and `update` do.

- **Invalid key in the `DELETE` URL:** A key that can't be coerced to the property-ref's type
  raises `OdataDuty::InvalidPropertyReferenceValue` (`Invalid individual id : ...`), the same
  conversion error `individual` and `update` produce.

- **MCP `delete_<Set>` for a set that lacks the capability:** Because the tool is never listed
  for such a set, calling it via `tools/call` raises an `"Unknown tool: <tool>"` error rather
  than `NoImplementationError`.

## Scope

**In scope**

- A `delete(id)` hook on **both** the class DSL (`OdataDuty::EntitySet`) and the builder DSL
  (`OdataDuty::SetResolver`), inferred by method presence.
- A new public entry point `schema.delete(url, context:, query_options:)` for the OData `DELETE`
  verb against an individual URL.
- Reflection across all three contracts: `delete` operation in `$oas2`, `DeleteRestrictions`
  annotation in `$metadata` (when absent), and `delete_<Set>` MCP tool.
- `204 No Content` success semantics; `ResourceNotFoundError` for a missing key.
- Rails generator support: the `install` generator emits a `destroy` action and `delete` route,
  and the `entity_set` generator scaffolds a `delete(id)` method (and a `#delete` spec example) in
  both DSL templates.

**Out of scope**

- Bulk / filtered deletes (`DELETE` against a collection or with `$filter`).
- Soft-delete or restore semantics.
- Composite keys (unsupported across the gem).
- Returning the deleted entity in the response body.

## Documentation impact

Extend the existing guide **`doc/using_create_and_update.md`** to cover `delete` as the third
write operation — ideally retitled to cover create / update / delete — keeping its purpose-first,
example-driven, "Common Error Cases" structure and updating the cross-references in `README.md`
(the "Implementing `create` makes a set insertable…" sentence and the Further Documentation list).
Also update **`doc/entity_set_generator.md`** to document the scaffolded `delete(id)` method and
the generated `destroy` action / `delete` route. Do not write either guide as part of this PRD.

## Open questions

- Should `delete_<Set>` and the REST `DELETE` return a structured confirmation payload (e.g. the
  deleted key) instead of a bare acknowledgement / `204`? Current decision: bare `204` /
  acknowledgement, matching OData convention.
- Should the generator work also close the pre-existing `update` gap (add the `patch` route,
  `update` controller action, and scaffolded `update(id, input)`) at the same time, or stay
  strictly scoped to `delete`? Current decision: scope to `delete`; note the gap for a follow-up.