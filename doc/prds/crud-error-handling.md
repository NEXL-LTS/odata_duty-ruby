# PRD: CRUD error handling & OData-compliant validation errors

## Summary

Give gem consumers a first-class way to **reject a `create` / `update` / `delete` with a
meaningful error** — a custom message, a service-defined code, and the offending field — and have
OdataDuty render that error in the OData v4 error envelope with the correct HTTP status. Today the
pieces exist (an error hierarchy that already knows its `status`, `code`, and `target`) but nothing
ties them together, so the reference controller flattens every failure to `500` with a non-OData
body. This PRD closes that gap.

## Goal / Problem

A consumer writing `create`/`update`/`delete` has no sanctioned way to say "this request is
invalid because `user_name` is already taken." Their only framework-supported signal is *return
falsey from `update`/`delete`* → `404 ResourceNotFoundError`. Anything else (a Rails
`RecordInvalid`, a hand-raised `RuntimeError`) propagates as a bare `StandardError`.

The reference wiring then makes it worse. `spec/config.ru` and the README controller both do:

```ruby
rescue StandardError => e
  [500, ..., JSON.generate({ error: 'Internal Server Error', message: e.message })]
```

So even framework errors that already know they are client errors come back wrong:

| Failure | What the consumer sees today | OData-correct |
|---|---|---|
| `POST` to a read-only set | `500` `{error:"Internal Server Error",...}` | `501` |
| `PATCH`/`DELETE` unknown key | `500` | `404` |
| Body value of wrong type | `500` | `400` |
| Consumer-rejected create (duplicate) | `500` (or an unhandled raise) | `400` with a real message |

The error metadata is present in the library (`RequestError#status`, `#code`, `#target`) and the
`$oas2` document already **advertises** an OData `Error` schema — but at runtime nothing emits that
shape and nothing reads `status`. The result: a consumer cannot return a useful validation message,
and the documented `$oas2` error contract is a promise the service never keeps.

**Current behavior:** all failures → `500`, ad-hoc `{error, message}` body, no way to set a custom
code/target/message from consumer code.

**Expected behavior:** consumer code can raise a typed validation error (or the framework raises one
of its existing typed errors); the service renders the OData v4 error envelope
`{"error":{"code","message","target","details"}}` with the status the error class already declares;
the reference controller and MCP path use it; `$oas2` documents the same shape.

## What it enables

- As a gem consumer, I can `raise OdataDuty::ValidationError.new("user_name is taken",
  code: "duplicate_user_name", target: "user_name")` from inside `create`/`update`/`delete` and
  have the client receive a `400` with that exact code, message, and target in the OData envelope.
- As a gem consumer, I can report **several** field errors at once via `details:` (e.g. `name` too
  long *and* `emails` empty) in a single `400` response.
- As a gem consumer, I get the **right HTTP status automatically** — `404` for a missing key, `400`
  for a bad body, `501` for an unsupported operation, `500` for an unexpected error — without
  writing a `case` over error classes in my controller.
- As a gem consumer, I can render any caught `OdataDuty` error with one call
  (`OdataDuty.render_error(e)`), so my controller's `rescue` is a one-liner.
- As an MCP client, a failed `create_<Set>` / `update_<Set>` / `delete_<Set>` tool call surfaces the
  same `code` / `message` / `target`, not just a bare message string.
- As an `$oas2` consumer, the documented `default` error response schema matches what the service
  actually returns.

**Scope limit:** this PRD does not add a declarative validation DSL (e.g. `validates` on a
property). Validation logic stays in the consumer's `create`/`update`; this PRD only standardizes
how the *result* of a failed validation is signaled and rendered.

## External API

Applies to **both DSLs** (class-based `EntitySet` and builder `SetResolver`) — the raise-and-render
behavior is identical because both already share the same `create`/`update`/`delete` contract.

### 1. Raising a validation error from consumer code

A new public error class, `OdataDuty::ValidationError` (a `ClientError`, so `status` is
`:bad_request` / `400`):

```ruby
OdataDuty::ValidationError.new(
  message,                 # human-readable string (required, positional)
  code: nil,               # service-defined string code, e.g. "duplicate_user_name"
  target: nil,             # the offending property/parameter name, e.g. "user_name"
  details: []              # optional array of { code:, message:, target: } for multi-field errors
)
```

Builder DSL (`SetResolver`):

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def create(input)
    if Person.exists?(user_name: input.user_name)
      raise OdataDuty::ValidationError.new(
        "The user_name '#{input.user_name}' is already taken.",
        code: "duplicate_user_name", target: "user_name"
      )
    end
    Person.create!(user_name: input.user_name, name: input.name, emails: input.emails)
  end

  def update(id, input)
    person = Person.find_by(id: id)
    return nil unless person                          # still → 404 ResourceNotFoundError

    errors = []
    if input.name && input.name.length > 100
      errors << { code: "too_long", target: "name", message: "Name exceeds 100 characters." }
    end
    if input.emails && input.emails.empty?
      errors << { code: "required", target: "emails", message: "At least one email is required." }
    end
    unless errors.empty?
      raise OdataDuty::ValidationError.new("Validation failed.", code: "validation_failed",
                                                                 details: errors)
    end

    person.update!(name: input.name) unless input.name.nil?
    person
  end
end
```

Class-based DSL (`EntitySet`) — identical, the set itself implements `create`/`update`/`delete`:

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def create(input)
    raise OdataDuty::ValidationError.new("Name is required.", code: "required", target: "name") \
      if input.name.nil?

    Person.create!(user_name: input.user_name, name: input.name, emails: input.emails)
  end
end
```

### 2. Rendering an error (consumer's controller)

Every `OdataDuty::Error` subclass that reaches the consumer exposes a stable public surface:

- `#status` → a symbol the consumer maps to an HTTP status (`:bad_request`, `:not_found`,
  `:not_implemented`, `:internal_server_error`). Already exists; this PRD makes it part of the
  documented public contract and ensures every relevant error returns the right one.
- `#to_odata_h` → the OData v4 envelope hash: `{ "error" => { "code", "message", "target",
  "details" } }`, omitting `target`/`details` when not set.

Plus one convenience entry point:

```ruby
OdataDuty.render_error(e) # => { status: :bad_request, body: { "error" => { ... } } }
```

The reference controller's `rescue` becomes a one-liner that uses these instead of forcing `500`:

```ruby
# app/controllers/api_controller.rb
def create
  render json: schema.create(params[:url], context: self, query_options: query_options), status: :created
rescue OdataDuty::Error => e
  rendered = OdataDuty.render_error(e)
  render json: rendered[:body], status: rendered[:status]
end
```

The matching `spec/config.ru` reference Rack app is updated the same way — it must map
`e.status` to the HTTP code and emit `e.to_odata_h`, replacing the blanket `StandardError → 500`.

> Design note (open for revision): the framework does **not** rescue inside `schema.create/...`;
> errors still propagate and the consumer owns the `rescue`, consistent with how the gem already
> leaves the controller/`config.ru` to the consumer. `render_error` + the public accessors make that
> `rescue` trivial. The alternative — having `schema.create` return a normalized result object — was
> considered but rejected to avoid changing the success-path return type. See Open Questions.

## Behavior & expected I/O

### Single-field validation failure (`POST`)

Request:

```http
POST /api/People
Content-Type: application/json

{ "user_name": "alice", "name": "Alice", "emails": ["alice@example.com"] }
```

Consumer `create` raises `ValidationError.new("...", code: "duplicate_user_name",
target: "user_name")`. Response:

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
```
```jsonc
{
  "error": {
    "code": "duplicate_user_name",
    "message": "The user_name 'alice' is already taken.",
    "target": "user_name"
  }
}
```

### Multi-field validation failure with `details[]` (`PATCH`)

```http
PATCH /api/People('1')
Content-Type: application/json

{ "name": "<101-char string>", "emails": [] }
```
```http
HTTP/1.1 400 Bad Request
```
```jsonc
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed.",
    "details": [
      { "code": "too_long", "target": "name",   "message": "Name exceeds 100 characters." },
      { "code": "required", "target": "emails", "message": "At least one email is required." }
    ]
  }
}
```

### Framework errors get the right status automatically (before → after)

| Request | Error class | Before | After |
|---|---|---|---|
| `POST` to read-only set | `NoImplementationError` | `500` ad-hoc body | `501` + envelope |
| `PATCH`/`DELETE` missing key | `ResourceNotFoundError` | `500` | `404` + envelope |
| Body value wrong type | `InvalidType` | `500` | `400` + envelope |
| Invalid key in URL | `InvalidPropertyReferenceValue` | `500` | `400` + envelope |
| Bug inside consumer `create` | `NoMethodError` (not an `OdataDuty::Error`) | `500` | `500` (unchanged — re-raised, not swallowed) |

Example — `DELETE` of a missing key:

```http
DELETE /api/People('999')
```
```http
HTTP/1.1 404 Not Found
```
```jsonc
{ "error": { "code": "not_found", "message": "No such entity 999" } }
```

Where a framework error has no service-defined code today, `code` defaults to a stable
snake_case string derived from the error (e.g. `not_found`, `not_implemented`, `bad_request`); the
exact default-code mapping is an implementation detail to settle during build, but every envelope
MUST carry a non-empty `code` and `message` (both required by OData v4).

### MCP / JSON-RPC

A failed `create_<Set>` / `update_<Set>` / `delete_<Set>` tool call currently returns the bare
`e.message` text. After this change the MCP error text carries the structured fields so an agent can
act on them — at minimum `code` and `target` alongside `message` (exact serialization to confirm at
build time, e.g. a JSON object in the tool response text). Resource-read errors are aligned the same
way.

### `$oas2`

The existing `definitions.Error` is extended so its documented shape matches the runtime envelope —
notably adding `details` as an array of `{ code, message, target }`:

```jsonc
{
  "definitions": {
    "Error": {
      "type": "object",
      "properties": {
        "error": {
          "type": "object",
          "properties": {
            "code":    { "type": "string", "description": "A service-defined error code." },
            "message": { "type": "string", "description": "A human-readable message." },
            "target":  { "type": "string", "description": "The target of the error.",
                         "x-nullable": true },
            "details": {
              "type": "array",
              "items": { "type": "object", "properties": {
                "code": {"type":"string"}, "message": {"type":"string"},
                "target": {"type":"string","x-nullable":true} } }
            }
          }
        }
      }
    }
  }
}
```

The `default` error response `$ref`'d by every operation is unchanged in wiring — it already points
at `#/definitions/Error`.

## Common error cases

- **Consumer raises `OdataDuty::ValidationError`** (with/without `code`/`target`/`details`):
  rendered as `400 Bad Request` with the OData envelope. `code` and `message` always present;
  `target` and `details` included only when set.
- **`POST`/`PATCH`/`DELETE` to a set lacking the operation:** `NoImplementationError` →
  `501 Not Implemented`. (Raised by the up-front capability check, unchanged.)
- **`PATCH`/`DELETE` for a key that doesn't exist** (consumer returns falsey):
  `ResourceNotFoundError` → `404 Not Found`. Unchanged signal; now rendered with the right status.
- **Invalid key in the `PATCH`/`DELETE` URL:** `InvalidPropertyReferenceValue` → `400`.
- **Request body fails coercion** (wrong type / unknown property accessed): `InvalidType` /
  `NoSuchPropertyError` → `400`.
- **A genuine `NoMethodError` (or other non-`OdataDuty::Error`) inside consumer `create`/`update`:**
  propagates unchanged and renders as `500` — it is a bug, not a client error, and is **not**
  rewritten into a `ValidationError` or `NoImplementationError`. (Preserves the existing behavior
  documented in `using_create_update_and_delete.md`.)
- **`ValidationError` raised from a read-only set's (nonexistent) `create`:** not reachable — the
  capability check raises `NoImplementationError` (`501`) before consumer code runs.

## Scope

**In:**
- New public `OdataDuty::ValidationError` (`ClientError` → `400`) with `message`/`code`/`target`/`details`.
- Public, documented `#status` and `#to_odata_h` on `OdataDuty::Error` (ensuring every relevant
  error returns the correct status and a complete envelope), plus `OdataDuty.render_error(e)`.
- `details[]` in the OData error envelope and the `$oas2` `Error` definition.
- Updating the reference wiring — `spec/config.ru` and the README/`using_create_update_and_delete.md`
  controller examples — to map `status` and emit the envelope.
- Aligning the MCP error path to surface `code`/`target` in addition to `message`.
- Both DSLs (class-based and builder) and both spec trees.

**Out:**
- A declarative validation DSL on properties (e.g. `validates`, `format:`, `length:`). Validation
  remains consumer logic.
- Having `schema.create/update/delete/execute` internally rescue and return a result object
  (success-path return type stays as-is). See Open Questions.
- New HTTP statuses beyond those the current hierarchy implies (e.g. `409`, `422`). The `status`
  contract is extensible later, but this PRD only standardizes `400`/`404`/`501`/`500`.
- Auth/authorization errors (`401`/`403`) — no auth concept exists in the gem today.

## Documentation impact

- **Extend** `doc/using_create_update_and_delete.md`: replace/expand its "Common Error Cases"
  section with the `ValidationError` raise pattern, the envelope shape, the status mapping table, and
  the updated controller `rescue`.
- **Update** `README.md`'s controller example to show the `rescue OdataDuty::Error` one-liner and
  correct statuses.
- Consider a short new guide `doc/error_handling.md` if the error-rendering surface (the envelope,
  `render_error`, status mapping, MCP alignment) outgrows the create/update/delete guide. Note only —
  do not write it unless requested.

## Open questions

1. **Render ownership.** This PRD has the consumer keep the `rescue` and call `render_error` /
   `e.to_odata_h` (least invasive). The alternative is for `schema.create/update/delete/execute` to
   rescue internally and return a normalized result the controller maps directly — cleaner controller,
   but it changes the success return type and is a bigger behavior change. Confirm the chosen shape.
2. **Default `code` for framework errors.** OData requires a non-empty `code`. Proposal: derive a
   stable snake_case code per error class (`not_found`, `not_implemented`, `bad_request`,
   `internal_server_error`). Confirm the exact strings, since clients may branch on them.
3. **MCP serialization.** Exact representation of the structured error in the MCP tool/resource
   response (full JSON object as text vs. a flat `"code: message"` string). Confirm during build.
4. **`InvalidValue`/`ServerError` status.** `InvalidValue` is currently a `ServerError`
   (`500`) even though some occurrences are arguably client input problems. Confirm whether any
   should be reclassified to `400`, or left as-is to avoid changing existing behavior.
