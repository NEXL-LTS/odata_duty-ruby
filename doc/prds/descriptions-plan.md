# Build plan: `description` — human-readable documentation on every schema element

PRD: [doc/prds/descriptions.md](descriptions.md)

## Architecture notes that shape this plan

- **`Property` (`lib/odata_duty/property.rb`, `property/single_prop.rb`, `property/collection_prop.rb`)
  is already shared** between both DSLs — `ComplexType.property` (class DSL) and
  `SchemaBuilder::ComplexType#property` (builder DSL) both funnel into the same
  `Property.new` factory. Adding `description:` once at that layer, plus once in
  `SingleProp#to_oas2`, automatically reaches `$oas2` property definitions **and** MCP
  input-schema properties (`create_`/`update_`/`get_` tools reuse `to_oas2`) for both DSLs.
- **`EnumMember` (`lib/odata_duty/enum_type.rb`) is already shared** — the builder DSL's
  `SchemaBuilder::EnumType#member` instantiates the same top-level `OdataDuty::EnumMember`
  the class DSL uses. One change covers both DSLs.
- **`$oas2` (`OdataDuty::OAS2.build_json` / `oas2.rb` / `oas2/*_path.rb`) only ever renders
  builder-DSL schemas today.** The class DSL (`OdataDuty::Schema`/`EntityType`/`ComplexType`/
  `EnumType`) has no `to_oas2` method and is never passed to `OAS2.build_json` — confirmed by
  grep (no `to_oas2` on any class-DSL metadata class, no call site passing a class-DSL schema).
  So: the `description:` **DSL surface** (macro/keyword + storage + validation) is needed on
  both DSLs for every element per the PRD, but **`$oas2` rendering work only touches
  builder-DSL files** (`schema_builder/*.rb`, `oas2.rb`, `oas2/*_path.rb`). `$metadata` and MCP
  rendering apply to both DSLs.
- **Builder DSL type hierarchy**: `SchemaBuilder::EntityType < SchemaBuilder::ComplexType <
  SchemaBuilder::DataType`; `SchemaBuilder::EnumType < SchemaBuilder::DataType`. Adding
  `description:` to `DataType#initialize` gives every builder type storage "for free"; each
  still needs its own `$metadata`/`$oas2` rendering since the ERB/`to_oas2` code differs per
  element kind.
- **Class DSL type hierarchy**: `EntityType < ComplexType` (so a `description` macro defined
  once on `ComplexType` is inherited by `EntityType`, mirroring how `property`/`properties`
  already work today). `EnumType`, `Schema`, and `EntitySet` are independent classes and each
  need their own macro.
- **MCP works for both DSLs already** (`McpServerBuilder.build` reads `schema.title`,
  `schema.version`, `schema.endpoints`; both `OdataDuty::Schema` class methods and
  `SchemaBuilder::Schema` provide these). `endpoint` objects differ per DSL
  (`EntitySet::Metadata` for class DSL vs `SchemaBuilder::Endpoint` wrapping
  `SchemaBuilder::EntitySet` for builder DSL) — both need a `description` accessor added.
- The PRD's "before" `$metadata` XML snippets are illustrative and may omit orthogonal
  existing annotations (e.g. `Capabilities.InsertRestrictions`) that the real fixture schema
  would also emit. Implementers should verify actual current output by running specs (mirror
  `spec/odata_duty/entity_set/immutable_metadata_spec.rb`'s style of asserting on the specific
  added annotation, not full-document byte-for-byte match against the PRD snippet) rather than
  treating the PRD XML as a literal fixture.
- A new `OdataDuty::InvalidDescriptionError < ArgumentError` (mirroring `InvalidNCNamesError`)
  and a small shared validation helper (mirroring how `Property.valid_name?` is a module method
  reused by both DSLs) should be introduced once, in Task 1, then reused by every later task.

## Shared "Common error cases" excerpt (applies to every task below)

> - **`OdataDuty::InvalidDescriptionError`** (a new `ArgumentError` subclass, matching
>   `InvalidNCNamesError` and `PropertyAlreadyDefinedError`) is raised when:
>   - the description is an empty string — `description: ''`
>   - the description is whitespace-only — `description: '   '`
>   - the value does not respond to `to_str` — `description: :people`, `description: 123`,
>     `description: ['a']`
>
>   The message names the element, e.g. `Person: description must be a non-empty string`.
> - **Omitting `description:` is never an error.** It is optional everywhere.
>   `description: nil` is treated the same as omitting it — no annotation, no `$oas2` key, no
>   MCP suffix — so a description interpolated from an optional source can be passed through
>   without a guard.
> - **No new request-time errors.** `description:` does not participate in `$filter`,
>   `$select`, `$search`, or create/update input coercion.
> - **Existing errors are unaffected.** `PropertyAlreadyDefinedError` still fires on a
>   duplicate property name regardless of descriptions; `InvalidNCNamesError` still fires on an
>   invalid property name and is raised *before* the description is validated.

---

## Task 1 — Property-level `description:` (both DSLs) + error class + shared validator

- [x] Status

**Full task text:** Add a `description:` keyword to property definitions in both DSLs
(`Property.new` in `lib/odata_duty/property.rb`, consumed identically by
`OdataDuty::ComplexType.property` for the class DSL and
`OdataDuty::SchemaBuilder::ComplexType#property` for the builder DSL — same underlying
factory, so one implementation covers both). Introduce `OdataDuty::InvalidDescriptionError <
ArgumentError` in `lib/odata_duty/errors.rb` and a small shared validation helper (e.g. a
module method alongside `Property.valid_name?` in `lib/odata_duty/property.rb`) that: treats
`nil`/omitted as "no description"; raises `InvalidDescriptionError` for an empty string,
a whitespace-only string, or a value that doesn't respond to `to_str`; otherwise returns the
description string. Store the resolved description on `Property::SingleProp` (and inherited by
`CollectionProp`). Render it into `$metadata`: in `lib/metadata.xml.erb`, both the
`ComplexType`/`EntityType` property-rendering blocks (lines ~21-33 and ~34-51) need updating so
a property with a description (and optionally also a mutability annotation) emits
`<Annotation Term="Org.OData.Core.V1.Description" String="..." />` **before** any
`Org.OData.Core.V1.Computed`/`Immutable` annotation, escaping XML special characters
(`&`, `"`, `<`). Render it into `$oas2`: add `'description' => description if description` to
`Property::SingleProp#to_oas2` (`lib/odata_duty/property/single_prop.rb`) — this alone flows
through to `$oas2` definitions' properties, the `PeopleCreate`/`PeopleUpdate` request-body
definitions, and MCP `create_`/`update_`/`get_` tool `inputSchema.properties`, since all of
these already call `p.to_oas2`. Do not let a property description collide with or shadow the
existing `odata_*` reserved MCP alias keys (confirm `McpIdentifierValidator`/`add_alias!`
collision behavior is unaffected — no code change expected there, just confirm with a test).
Cover both `spec/odata_duty/entity_set/**` (class DSL) and
`spec/odata_duty/schema_builder/**` (builder DSL) spec trees.

**Definition of done (PRD excerpts):**

> `property 'name', String, description: 'First name or full name'` ... have that text appear
> in `$metadata`, in the `$oas2` `Person` definition, and as the argument description on the
> MCP `create_People` / `update_People` tools — from one declaration.

> A property that carries both a description and a mutability annotation gets both children,
> in that order:
> ```xml
> <Property Name="id" Nullable="false" Type="Edm.String">
>     <Annotation Term="Org.OData.Core.V1.Description" String="Server-assigned identifier" />
>     <Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />
> </Property>
> ```
> XML special characters in a description are escaped (`&` → `&amp;`, `"` → `&quot;`,
> `<` → `&lt;`) so the document stays well-formed.

> `$oas2` definitions gain per-property `"description"`:
> ```jsonc
> "user_name": { "type": "string", "description": "Unique login handle" }
> ```
> The `PeopleCreate` / `PeopleUpdate` request-body definitions inherit property descriptions,
> since they are built from the same per-property rendering as the shared `Person` definition.

> MCP: property descriptions reach the write and key tools:
> ```jsonc
> {
>   "name": "create_People",
>   "inputSchema": { "properties": {
>     "user_name": { "type": "string", "description": "Unique login handle" }
>   } }
> }
> ```
> The reserved `odata_*` query-option keys keep their existing framework descriptions; a
> property description never overwrites one (the existing `InvalidMcpIdentifierError` collision
> check is unaffected).

Plus the shared "Common error cases" excerpt above (property is the first element to need it).

**Likely files:**
- `lib/odata_duty/errors.rb` (new `InvalidDescriptionError`)
- `lib/odata_duty/property.rb` (validation helper, `Property.new` keyword)
- `lib/odata_duty/property/single_prop.rb` (`description` storage, `to_oas2`)
- `lib/metadata.xml.erb` (Property annotation rendering, both ComplexType and EntityType blocks)
- `spec/odata_duty/entity_set/**` (new spec(s), e.g. `description_spec.rb`,
  `*_metadata_spec.rb`-style)
- `spec/odata_duty/schema_builder/**` (mirrored specs)
- `spec/odata_duty/oas2/**` (property description in `$oas2` definitions)
- MCP specs under `spec/odata_duty/entity_set/**` covering `create_`/`update_`/`get_` tool
  input schemas

**Dependencies:** none (first task).

---

## Task 2 — Schema-level `description:` (both DSLs)

- [x] Status

**Full task text:** Add a `description:` macro to the class DSL `OdataDuty::Schema`
(`lib/odata_duty.rb`, alongside `namespace`/`version`/`title`, but — unlike those — validated
via the Task 1 helper) and a `description` accessor to the builder DSL
`OdataDuty::SchemaBuilder::Schema` (`lib/odata_duty/schema_builder.rb`, alongside the existing
`attr_accessor :version, :title`, with validation on assignment). Render into `$metadata`: in
`lib/metadata.xml.erb`, add `<Annotation Term="Org.OData.Core.V1.Description" ... />` on
`<Schema>` immediately after the existing `Version`/`Title` annotations (~line 12). Render into
`$oas2`: in `lib/odata_duty/oas2.rb`'s `initialize`, add `info['description'] = schema.description
if schema.description` alongside the existing `info['version']`/`info['title']` lines. Render
into MCP: in `lib/odata_duty/mcp_server_builder.rb#build`, pass `instructions: schema.description`
to `MCP::Server.new` **only when present** (omitting the keyword — or passing nil — when there
is no schema description, so output stays byte-identical to today when omitted).

**Definition of done (PRD excerpts):**

> | Declared on | `$metadata` (EDMX) | `$oas2` | MCP |
> | Schema | `Org.OData.Core.V1.Description` annotation on `<Schema>` | `info.description` |
>   `instructions` in the `initialize` result |

> Before:
> ```xml
> <Annotation Term="Sample.Version" String="1.0" />
> <Annotation Term="Sample.Title" String="Sample Service" />
> ```
> After:
> ```xml
> <Annotation Term="Sample.Version" String="1.0" />
> <Annotation Term="Sample.Title" String="Sample Service" />
> <Annotation Term="Org.OData.Core.V1.Description" String="Directory of people attending the annual conference" />
> ```

> `$oas2` after:
> ```jsonc
> "info": {
>   "version": "1.0",
>   "title": "Sample Service",
>   "description": "Directory of people attending the annual conference"
> }
> ```

> MCP: Schema-level description becomes the server `instructions`:
> ```jsonc
> // initialize result
> {
>   "protocolVersion": "2025-06-18",
>   "capabilities": { "tools": {} },
>   "serverInfo": { "name": "Sample Service", "version": "1.0" },
>   "instructions": "Directory of people attending the annual conference"
> }
> ```
> Without a schema description, `instructions` is absent — exactly today's output.

> **Schema → nothing else**: `serverInfo.description` exists in `mcp` 0.25.0 but is silently
> dropped for negotiated protocol version ≤ `2025-06-18`, and `MCP::Server#validate!` raises
> `ArgumentError` on it in that range. `instructions` is emitted at every protocol version, so it
> is the sole schema-level MCP target.

Plus the shared "Common error cases" excerpt above, applied to the schema-level
`description`/`description=`.

**Likely files:**
- `lib/odata_duty.rb` (`Schema.description` class macro)
- `lib/odata_duty/schema_builder.rb` (`Schema#description=`/accessor with validation)
- `lib/metadata.xml.erb` (Schema-level Annotation)
- `lib/odata_duty/oas2.rb` (`info['description']`)
- `lib/odata_duty/mcp_server_builder.rb` (`instructions:` on `MCP::Server.new`)
- `spec/odata_duty/entity_set/**`, `spec/odata_duty/schema_builder/**`,
  `spec/odata_duty/oas2/**` specs

**Dependencies:** Task 1 (reuses the validation helper and `InvalidDescriptionError`).

---

## Task 3 — Entity type & complex type `description:` (both DSLs)

- [x] Status

**Full task text:** Add a `description` class macro to the class DSL `OdataDuty::ComplexType`
(`lib/odata_duty/complex_type.rb`) — validated via the Task 1 helper — which `EntityType`
inherits automatically (mirrors how `property`/`properties` are already shared this way; no
separate macro needed on `EntityType` itself). Add `description:` as a keyword on
`OdataDuty::SchemaBuilder::DataType#initialize` (`lib/odata_duty/schema_builder/data_type.rb`)
with the same validation — this gives `SchemaBuilder::ComplexType` and (via inheritance)
`SchemaBuilder::EntityType` a `description` reader "for free" (it also reaches `EnumType`,
which Task 4 will use). Render into `$metadata`: in `lib/metadata.xml.erb`, add the
`Org.OData.Core.V1.Description` annotation as the **first child** of `<ComplexType Name="...">`
(before the properties loop, ~line 22) and of `<EntityType Name="...">` (before `<Key>`,
~line 35) when present. Render into `$oas2` (**builder DSL only** — the class DSL has no
`to_oas2`/`$oas2` rendering path at all today, confirmed by grep): add
`'description' => description if description` to
`OdataDuty::SchemaBuilder::ComplexType#to_oas2` (`lib/odata_duty/schema_builder/complex_type.rb`)
— since `SchemaBuilder::EntityType` inherits this `to_oas2` unchanged, entity types get the same
`definitions.<Type>.description` for free.

**Definition of done (PRD excerpts):**

> | Entity type | `Org.OData.Core.V1.Description` on `<EntityType>` |
>   `definitions.<Type>.description` | — |
> | Complex type | `Org.OData.Core.V1.Description` on `<ComplexType>` |
>   `definitions.<Type>.description` | — |
> **Entity / complex / enum type → MCP**: MCP tools are entity-*set*-scoped ... type
> descriptions are intentionally not surfaced over MCP.

> `$metadata` after:
> ```xml
> <EntityType Name="Person">
>     <Annotation Term="Org.OData.Core.V1.Description" String="People present at the event" />
>     <Key><PropertyRef Name="id" /></Key>
>     ...
> </EntityType>
> ```

> `$oas2` after:
> ```jsonc
> "Person": {
>   "type": "object",
>   "description": "People present at the event",
>   "properties": { ... }
> }
> ```

Plus the shared "Common error cases" excerpt above, applied to entity-type and complex-type
`description`.

**Likely files:**
- `lib/odata_duty/complex_type.rb` (`description` class macro, inherited by `EntityType`)
- `lib/odata_duty/schema_builder/data_type.rb` (`description:` keyword + validation)
- `lib/odata_duty/schema_builder/complex_type.rb` (`to_oas2` gains `description`)
- `lib/metadata.xml.erb` (ComplexType and EntityType annotation placement)
- `spec/odata_duty/entity_set/**`, `spec/odata_duty/schema_builder/**`,
  `spec/odata_duty/oas2/**` specs

**Dependencies:** Task 1.

---

## Task 4 — Enum type & enum member `description:` (both DSLs)

- [x] Status

**Full task text:** Add a `description` class macro to the class DSL `OdataDuty::EnumType`
(`lib/odata_duty/enum_type.rb`) — validated via the Task 1 helper (the builder DSL side already
gets a `description` reader for free from Task 3's `DataType#initialize` change, since
`SchemaBuilder::EnumType < DataType`). Add `description:` as a keyword on the shared
`OdataDuty::EnumMember#initialize` (`lib/odata_duty/enum_type.rb`) with the same validation —
this single class is instantiated by both `EnumType.member` (class DSL) and
`SchemaBuilder::EnumType#member` (builder DSL), so one change covers both. Render into
`$metadata`: in `lib/metadata.xml.erb`, add the type-level Annotation as the first child of
`<EnumType Name="...">` (before the members loop, ~line 15), and change each
`<Member Name="..." />` to open a child `<Annotation ...>` when the member has a description
(same open/self-close pattern already used for properties). Render into `$oas2`
(**builder DSL only**): add `'description' => description if description` to
`OdataDuty::SchemaBuilder::EnumType#to_oas2` (`lib/odata_duty/schema_builder/enum_type.rb`).
Enum **member** descriptions have no `$oas2` slot (Swagger 2.0 has no per-enum-value
description) — do not add one.

**Definition of done (PRD excerpts):**

> | Enum type | `Org.OData.Core.V1.Description` on `<EnumType>` |
>   `definitions.<Type>.description` | — |
> | Enum member | `Org.OData.Core.V1.Description` on `<Member>` | — | — |
> **Enum member → `$oas2`**: Swagger 2.0 has no per-enum-value description slot. `$metadata`
> only.

> `$metadata` after:
> ```xml
> <EnumType Name="Gender">
>     <Annotation Term="Org.OData.Core.V1.Description" String="Gender as recorded at registration" />
>     <Member Name="Male">
>         <Annotation Term="Org.OData.Core.V1.Description" String="Recorded as male" />
>     </Member>
>     <Member Name="Female">
>         <Annotation Term="Org.OData.Core.V1.Description" String="Recorded as female" />
>     </Member>
> </EnumType>
> ```

> `$oas2` after:
> ```jsonc
> "Gender": {
>   "type": "string",
>   "enum": ["Male", "Female"],
>   "description": "Gender as recorded at registration"
> }
> ```

> Class DSL:
> ```ruby
> class GenderEnum < OdataDuty::EnumType
>   description 'Gender as recorded at registration'
>   member 'Male',   description: 'Recorded as male'
>   member 'Female', description: 'Recorded as female'
> end
> ```
> Builder DSL:
> ```ruby
> gender = s.add_enum_type(name: 'Gender',
>                          description: 'Gender as recorded at registration') do |e|
>   e.member 'Male',   description: 'Recorded as male'
>   e.member 'Female', description: 'Recorded as female'
> end
> ```

Plus the shared "Common error cases" excerpt above, applied to enum-type and enum-member
`description`.

**Likely files:**
- `lib/odata_duty/enum_type.rb` (`EnumType.description` class macro, `EnumMember` gains
  `description:`)
- `lib/odata_duty/schema_builder/enum_type.rb` (`to_oas2` gains `description`)
- `lib/metadata.xml.erb` (EnumType and Member annotation placement)
- `spec/odata_duty/entity_set/**`, `spec/odata_duty/schema_builder/**`,
  `spec/odata_duty/oas2/**` specs

**Dependencies:** Task 1; Task 3 (for the builder-DSL `DataType#initialize` change that
`SchemaBuilder::EnumType` inherits — confirm it's already in place before starting).

---

## Task 5 — Entity set `description:` (both DSLs): `$metadata`, `$oas2` operations, MCP tool suffix

- [x] Status

**Full task text:** Add a `description` class macro to the class DSL `OdataDuty::EntitySet`
(`lib/odata_duty.rb`, alongside `entity_type`/`name`/`url`, validated via the Task 1 helper) and
a `description:` keyword to the builder DSL `OdataDuty::SchemaBuilder::EntitySet#initialize`
(`lib/odata_duty/schema_builder/entity_set.rb`, alongside `entity_type:`/`resolver:`/`name:`/
`url:`/`init_args:`, validated the same way). Expose it on both endpoint-shaped wrappers used
downstream: `EntitySet::Metadata#description` (class DSL, `lib/odata_duty.rb`) and
`SchemaBuilder::Endpoint#description` (builder DSL, `lib/odata_duty/schema_builder/endpoint.rb`,
delegating to the wrapped `entity_set`). Render into `$metadata`: in `lib/metadata.xml.erb`, add
`Org.OData.Core.V1.Description` as a child of `<EntitySet Name="...">` — verify against the
existing capability-annotation conditionals (`SearchRestrictions`/`FilterRestrictions`/
`InsertRestrictions`/etc., ~lines 54-110) so the description annotation coexists correctly
regardless of which capability annotations also fire for a given set; base placement/ordering on
what real spec runs show, not solely the PRD's simplified snippet. Render into `$oas2`
(**builder DSL only**): every operation on that set's collection and individual paths gains a
`summary` (mirroring the exact verb text already used for MCP tool descriptions — see below) and
`description` (the set's description) — but **only when the set has a description**; a set
without one keeps today's exact output (no `summary`, no `description`). Touches
`lib/odata_duty/oas2/collection_get_path.rb`, `collection_post_path.rb`,
`individual_get_path.rb`, `individual_patch_path.rb`, `individual_delete_path.rb`. Render into
MCP: in `lib/odata_duty/mcp_server_builder.rb`, every tool for that set (`list_`, `count_`,
`get_`, `create_`, `update_`, `delete_`) gets its `description` suffixed with
`". #{entity_set_description}"` when present — the generated verb text stays first. Since the
PRD requires the `$oas2` `summary` text to exactly equal the MCP tool's generated verb text
(e.g. both must say `"List People records"` for the list operation), consider extracting each
verb-text string into one shared place read by both `mcp_server_builder.rb` and the `oas2/*.rb`
path builders, so the two contracts cannot drift — the exact verb strings already exist in
`mcp_server_builder.rb` (`"List #{name} records"`, `"Count #{name} records"`,
`"Create a new #{name} record"`, `"Get a single #{name} record by ID"`,
`"Update an existing #{name} record"`, `"Delete an existing #{name} record"`).

**Definition of done (PRD excerpts):**

> | Entity set | `Org.OData.Core.V1.Description` on `<EntitySet>` | operation `summary` +
>   `description` | appended to each tool's `description` |

> `$metadata` after:
> ```xml
> <EntitySet Name="People" EntityType="Sample.Person">
>     <Annotation Term="Org.OData.Core.V1.Description" String="Attendees checked in at the front desk" />
> </EntitySet>
> ```

> `$oas2` after:
> ```jsonc
> "/People": {
>   "get": {
>     "operationId": "GetCollectionOfPeople",
>     "summary": "List People records",
>     "description": "Attendees checked in at the front desk",
>     "produces": ["application/json"],
>     "parameters": [ /* ... */ ]
>   },
>   "post": {
>     "operationId": "CreatePeople",
>     "summary": "Create a new People record",
>     "description": "Attendees checked in at the front desk"
>   }
> },
> "/People({id})": {
>   "get":    { "summary": "Get a single People record by ID", "description": "Attendees checked in at the front desk" },
>   "patch":  { "summary": "Update an existing People record",  "description": "Attendees checked in at the front desk" },
>   "delete": { "summary": "Delete an existing People record",  "description": "Attendees checked in at the front desk" }
> }
> ```
> `summary` is the same generated verb text used for the MCP tool of the same operation, so the
> two contracts stay consistent. Operations get a `summary` **only** when the set has a
> description; a set without one keeps today's exact output (no `summary`, no `description`).

> MCP after:
> ```jsonc
> {
>   "name": "list_People",
>   "description": "List People records. Attendees checked in at the front desk",
>   "inputSchema": { ... }
> }
> ```
> Tool descriptions gain the set description as a suffix, joined to the generated text with
> `". "` — the verb stays first so an agent can still tell `list_` from `count_` from `delete_`.

> As a gem consumer, I can describe an entity set once and have that description enrich
> **every** MCP tool for that set (`list_`, `count_`, `get_`, `create_`, `update_`, `delete_`)
> so an agent understands the domain, not just the verb.

Plus the shared "Common error cases" excerpt above, applied to entity-set `description`.

**Likely files:**
- `lib/odata_duty.rb` (`EntitySet.description` class macro, `EntitySet::Metadata#description`)
- `lib/odata_duty/schema_builder/entity_set.rb` (`description:` keyword)
- `lib/odata_duty/schema_builder/endpoint.rb` (`description` delegator)
- `lib/metadata.xml.erb` (EntitySet annotation)
- `lib/odata_duty/oas2/collection_get_path.rb`, `collection_post_path.rb`,
  `individual_get_path.rb`, `individual_patch_path.rb`, `individual_delete_path.rb`
  (`summary`/`description`)
- `lib/odata_duty/mcp_server_builder.rb` (tool description suffix)
- `spec/odata_duty/entity_set/**`, `spec/odata_duty/schema_builder/**`,
  `spec/odata_duty/oas2/**` specs, MCP tool-description specs

**Dependencies:** Task 1 (validation helper); independent of Tasks 2-4 otherwise.

---

## Task 6 — Documentation impact

- [ ] Status

**Full task text:** Add a new guide `doc/using_descriptions.md`, styled like
`doc/using_computed.md` and `doc/using_mutability.md`: purpose-first overview, both-DSL
snippets for every element (schema, entity type, complex type, enum type, enum member,
property/`property_ref`, entity set), a section per output contract (`$metadata`/`$oas2`/MCP)
showing rendered before/after, and a closing "Common errors / edge cases" section covering
`InvalidDescriptionError` and the `nil`-is-omitted rule. Carry over the "Where each description
lands" table from the PRD verbatim. Then update: `CLAUDE.md` — add a `**Descriptions**` bullet
to the `## Features` list pointing at the new guide (matching the existing bullet style, e.g. the
`**Property mutability**` bullet). `README.md` — add `description:` to the entity-type/property
example so it's visible in the first schema a reader sees. `doc/using_mcp.md` — note that tool
descriptions incorporate the entity-set description and that a schema description becomes the
server `instructions`. `doc/using_oas2.md` — note the new `info.description`, definition,
property, and operation `summary`/`description` output.

**Definition of done (PRD excerpt):**

> Add a **new guide**, `doc/using_descriptions.md`, in the style of `doc/using_computed.md` and
> `doc/using_mutability.md`: purpose-first, both-DSL snippets, a section per output contract
> (`$metadata` / `$oas2` / MCP) showing the rendered result, and a closing
> "Common errors / edge cases" section. The where-each-description-lands table above should
> carry over.
>
> Also update:
> - **`CLAUDE.md`** — add a `**Descriptions**` bullet to the Features list pointing at the new
>   guide.
> - **`README.md`** — add `description:` to the entity-type / property example so it is visible
>   in the first schema a reader sees.
> - **`doc/using_mcp.md`** — note that tool descriptions incorporate the entity-set description
>   and that a schema description becomes the server `instructions`.
> - **`doc/using_oas2.md`** — note the new `info.description`, definition, property, and
>   operation `summary`/`description` output.

**Likely files:** `doc/using_descriptions.md` (new), `CLAUDE.md`, `README.md`,
`doc/using_mcp.md`, `doc/using_oas2.md`.

**Dependencies:** Tasks 1-5 (documents the finished behavior).
