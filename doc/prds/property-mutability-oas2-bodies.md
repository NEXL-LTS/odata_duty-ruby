# PRD: Per-operation `$oas2` request-body schemas

> **Part C of 3** — see [`property-mutability-constraints.md`](property-mutability-constraints.md)
> for the umbrella overview. Builds on Part A
> ([`property-mutability-immutable.md`](property-mutability-immutable.md)) and Part B
> ([`property-mutability-non-insertable.md`](property-mutability-non-insertable.md)), which
> added the `:immutable` and `:non_insertable` states with runtime + `$metadata` + MCP support
> but left `$oas2` unchanged. This part makes those states correct in `$oas2`.

## Summary

Emit a **separate request-body definition per write operation** in `$oas2` —
`<Entity>Create` for `POST` and `<Entity>Update` for `PATCH` — alongside the existing
`<Entity>` response definition. This expresses create-only / update-only settability
structurally (by which fields are in which body), the only form Microsoft Power Automate /
Logic Apps custom connectors actually honor.

## Goal / Problem

After Parts A and B, `:immutable` and `:non_insertable` are enforced at runtime and described
in `$metadata` and the MCP tools — but **`$oas2` still advertises them as freely writable**,
because both the `post` and `patch` bodies reference one shared `#/definitions/<Entity>`. A
single shared schema cannot say "this field is settable on create but not update."

A field-level annotation like `x-ms-mutability` does **not** solve this: it is an AutoRest
SDK-generation extension, **not** one the Power Platform connector engine reads (verified
against Microsoft's custom-connector OpenAPI-extensions documentation — the supported set is
`x-ms-summary`, `x-ms-visibility`, `x-ms-dynamic-*`, etc.; `x-ms-mutability` is absent). The
representation Power Automate honors is **separate operations with separate bodies** — Create
and Update are distinct connector actions — so the fix is structural, not an annotation.

## What it enables

- *As a Power Automate / connector author, when I import the `$oas2`, the Create action shows
  only create-settable fields and the Update action shows only update-settable fields* — the
  immutable/non-insertable distinction from Parts A and B is finally visible in the tool.
- *As any OAS2 consumer, the request and response contracts are explicit and distinct* rather
  than overloading one definition with `readOnly` hints.

## External API

No DSL change — this part is purely about the generated `$oas2`. It consumes the `mutability:`
values defined in Parts A and B.

## Behavior & expected I/O

### Three definitions per writable entity

- **`<Entity>`** — the **response** schema (GET / collection / individual / create and update
  response bodies). Every property. A `:computed` property keeps `readOnly: true`; no other
  mutability annotation.
- **`<Entity>Create`** — the **`POST` request body**. Only properties settable on create
  (`:read_write` + `:immutable`); `:computed` and `:non_insertable` omitted.
- **`<Entity>Update`** — the **`PATCH` request body**. Only properties settable on update
  (`:read_write` + `:non_insertable`); `:computed` and `:immutable` omitted. (The key travels
  in the path, not the body.)

```jsonc
{
  "definitions": {
    "Order": {                              // response schema — every property
      "properties": {
        "id":             { "type": "string", "readOnly": true },
        "account_number": { "type": "string" },
        "status":         { "type": "string" },
        "created_at":     { "type": "string", "format": "date-time", "readOnly": true },
        "note":           { "type": "string" }
      }
    },
    "OrderCreate": {                        // POST body — :read_write + :immutable
      "properties": {
        "account_number": { "type": "string" },   // :immutable — settable on create
        "note":           { "type": "string" }    // :read_write
      },
      "required": ["account_number"]
    },
    "OrderUpdate": {                        // PATCH body — :read_write + :non_insertable
      "properties": {
        "status": { "type": "string" },            // :non_insertable — settable on update
        "note":   { "type": "string" }             // :read_write
      }
    }
  }
}
```

The `post` operation's `body` parameter references `#/definitions/OrderCreate`; the `patch`
operation's references `#/definitions/OrderUpdate`. Both still respond with the full
`#/definitions/Order` (`200`/`201`).

### Emitted for every writable set

These per-operation body definitions are emitted for **every** create-able / update-able set —
even one with no constrained properties, where the body simply equals the writable set — so
the `$oas2` shape is uniform and predictable.

`x-ms-mutability` is **not** emitted; the per-operation bodies carry the distinction in a form
Power Automate honors, and `readOnly` covers the computed case in the response definition.

### Change to existing output

This **changes today's `$oas2`**: the `post`/`patch` bodies stop referencing the shared
`#/definitions/<Entity>` and reference the new per-operation definitions instead. This applies
even to entities with no `:immutable`/`:non_insertable` properties.

## Common error cases

None new — this part only changes document generation. No runtime behavior or validation
changes.

## Scope

**In scope**

- Emit `<Entity>Create` and `<Entity>Update` request-body definitions, with field membership
  by `mutability:` as above, for every writable set.
- Point the `post` body at `<Entity>Create` and the `patch` body at `<Entity>Update`; keep
  responses on `<Entity>`; keep `readOnly: true` on `:computed` in `<Entity>`.
- Do **not** emit `x-ms-mutability`.
- Implement for **both** DSLs, with matching specs under **both**
  `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`.

**Out of scope**

- Any DSL or runtime change (Parts A/B own those).
- `$metadata` and MCP (already correct after Parts A/B).
- A `delete` body (DELETE carries none).

## Documentation impact

Update **`doc/using_mutability.md`** with the `$oas2` section (the three definitions and the
per-operation body mapping) and remove any "`$oas2` deferred" notes left by Parts A/B. Update
**`doc/using_create_update_and_delete.md`**: its `$oas2` examples currently show the
`post`/`patch` bodies referencing the shared `#/definitions/<Entity>` — revise them to
`#/definitions/<Entity>Create` and `#/definitions/<Entity>Update`, including for sets with no
constrained properties.

## Open questions

None.
