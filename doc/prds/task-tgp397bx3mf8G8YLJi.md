# Reflect unimplemented `create` in `$metadata`, `$oas2`, and MCP

## Summary
When an entity set's data class (class DSL) or resolver (builder DSL) does **not** implement
`create`, the generated `$metadata` EDMX, `$oas2` JSON, and MCP tool list should all reflect that
creation is unavailable for that set. Conversely, sets that **do** implement `create` advertise it —
including a new `create_<EntitySet>` MCP tool. This is for gem consumers who expose read-only (or
selectively writable) entity sets and want their generated contracts to tell the truth.

## Goal / Problem
Today an entity set's *read* capability is already reflected accurately: the builder DSL only emits
OAS2 GET paths for sets that implement `collection` / `individual` (`collection_entity_sets` /
`individual_entity_sets`), and `Capabilities.SearchRestrictions` is annotated only when `od_search`
exists. **Create is the exception:**

- **`$oas2`** emits a `post` operation on *every* collection path (`add_collection_paths`), even for
  read-only sets that never implement `create`. Consumers see a POST in their Swagger that 4xx's at
  runtime.
- **`$metadata`** says nothing at all about insert capability.
- **MCP** exposes no create affordance in either direction.

Expected behavior: the three generated outputs should agree with what the data class/resolver
actually implements, the same way they already do for read and search.

## What it enables
- As a gem consumer, when my resolver does **not** define `create`, my `$oas2` document omits the
  `post` operation for that set, so generated clients don't offer a non-functional create.
- As a gem consumer, my `$metadata` carries `Capabilities.InsertRestrictions` with
  `Insertable="false"` for read-only sets, so OData-aware clients know not to attempt inserts.
- As a gem consumer, when my resolver **does** define `create`, an MCP `create_<EntitySet>` tool
  appears in `tools/list` and can be called to create a record; when it doesn't, no such tool is
  listed.

Scope limit: this covers `create` only. `update`/PATCH does not exist in the gem and is explicitly
out of scope (see Scope).

## External API
No new consumer-written declaration is introduced — availability is inferred from whether the data
class/resolver implements `create`, mirroring how `collection`, `individual`, and `od_search` are
already detected.

**Builder DSL** — a read-only resolver vs. a writable one:

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init = @records = People.all
  def collection = @records
  def individual(id) = @records.find { |r| r.id == id }
  # no #create  → create is unavailable for this set
end

class WidgetsResolver < OdataDuty::SetResolver
  def od_after_init = @records = Widgets.all
  def collection = @records
  def create(input)            # presence of #create → create is available
    Widgets.create!(name: input.name)
  end
end
```

**Class-based DSL** — same inference via the entity set class:

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity
  def collection = People.all
  # no #create  → create is unavailable
end

class WidgetsSet < OdataDuty::EntitySet
  entity_type WidgetEntity
  def collection = Widgets.all
  def create(input) = Widgets.create!(name: input.name)
end
```

Detection contract: a set "supports create" when its resolver/data class responds to `create`
(`resolver_class.method_defined?(:create)` for the builder DSL; the entity-set class equivalent for
the class DSL) — analogous to the existing `supports_search?` predicate. No new public method is
required of consumers.

## Behavior & expected I/O

**`$oas2` — read-only set (`People`, no `create`):** only `get` is emitted.

```jsonc
"paths": {
  "/People": {
    "get": { "operationId": "ListPeople", "...": "..." }
    // no "post"
  },
  "/People({id})": { "get": { "operationId": "GetPeople", "...": "..." } }
}
```

**`$oas2` — writable set (`Widgets`, has `create`):** unchanged from today — both `get` and `post`.

```jsonc
"paths": {
  "/Widgets": {
    "get":  { "operationId": "ListWidgets", "...": "..." },
    "post": { "operationId": "CreateWidgets", "...": "..." }
  }
}
```

**`$metadata` EDMX — read-only set** gets an `InsertRestrictions` annotation (writable sets get no
such annotation, i.e. default-insertable):

```xml
<EntitySet Name="People" EntityType="MyNamespace.Person">
  <Annotation Term="Capabilities.InsertRestrictions">
    <Record>
      <PropertyValue Property="Insertable" Bool="false" />
    </Record>
  </Annotation>
</EntitySet>
<EntitySet Name="Widgets" EntityType="MyNamespace.Widget" />
```

(The `Org.OData.Capabilities.V1` reference is already declared at the top of the EDMX document, as
used by `SearchRestrictions`.)

**MCP `tools/list`** — a `create_<EntitySet>` tool is listed for each set that implements `create`
(alongside any `search_<EntitySet>` tools), and omitted for read-only sets:

```jsonc
{ "tools": [
  { "name": "create_Widgets",
    "description": "Create a new Widgets record",
    "inputSchema": {
      "type": "object",
      "properties": { "name": { "type": "string" }, "...": "..." },
      "required": ["name"]
    } }
  // no create_People
] }
```

The `create_<EntitySet>` tool's `inputSchema` mirrors the entity type's writable input shape (the
same body schema the OAS2 `post` advertises). A `tools/call` for `create_Widgets` creates the record
and returns the created entity as structured JSON — reusing the existing create path
(`Schema.create` / `Executor.create`), the same way `search_<EntitySet>` reuses the read path today.

**Runtime REST POST** behavior is unchanged: a POST to a set without `create` still raises
`NoImplementationError` ("create not implemented"). The outputs simply no longer *advertise* the
unavailable operation.

## Common error cases
- **POST to a set without `create`** (class or builder DSL): raises `NoImplementationError` —
  "create not implemented for <set>". Unchanged; the outputs now just don't advertise it.
- **MCP `tools/call` for `create_<EntitySet>` on a read-only set**: the tool is not in `tools/list`,
  so calling it raises the existing "Unknown tool" error.
- **MCP `create_<EntitySet>` with a body that fails coercion/validation**: surfaces the existing
  creation errors (e.g. `InvalidValue` / `UnknownPropertyError`) from the create path, as a
  JSON-RPC error.
- Read-side errors (`ResourceNotFoundError`, `InvalidQueryOptionError`, etc.) are unaffected.

## Scope
- **In:** detecting `create` availability per entity set; gating the OAS2 `post` path on it; adding
  `Capabilities.InsertRestrictions` (`Insertable=false`) to `$metadata` for non-creatable sets;
  adding a `create_<EntitySet>` MCP tool for creatable sets. Both the class-based DSL and the builder
  DSL, with mirrored specs in `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`.
- **Out:** `update`/PATCH (no such operation exists in the gem); delete; per-property insert
  restrictions; changing the runtime POST execution/coercion behavior; `Updatable` /
  `UpdateRestrictions` annotations.

## Documentation impact
Add a new guide `doc/using_create.md` in the house style (purpose-first, example-driven, ending in
"Common Error Cases"), covering: how implementing `create` makes a set writable, how omitting it
makes the set read-only, and how that choice is reflected across `$oas2`, `$metadata`, and MCP.
Cross-link it from the create-related parts of `README.md`. (Guide not written as part of this PRD.)

## Open questions
- MCP `create_<EntitySet>` `inputSchema`: reflect **all** entity-type properties, or only
  non-key/writable ones? Default assumption above is "the same writable body shape OAS2's `post`
  advertises."