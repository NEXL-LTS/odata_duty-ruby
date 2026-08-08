# Using `$oas2` (OpenAPI/Swagger) with OdataDuty

`OdataDuty::OAS2.build_json(schema)` renders your schema as an [OpenAPI 2.0 (Swagger)](https://swagger.io/specification/v2/) document. The Rails integration serves it at `/$oas2`, so tools that consume Swagger — API explorers, code generators, and low-code platforms like Microsoft Power Automate — can build a client from your service.

`OAS2.build_json` requires a builder-DSL schema (`SchemaBuilder.build`), not a class-based `Schema`.

A `description:` declared anywhere in the schema (see
[`doc/using_descriptions.md`](using_descriptions.md)) flows into this document: a schema
description becomes `info.description`; entity/complex/enum type descriptions become
`definitions.<Type>.description`; property descriptions become
`definitions.<Type>.properties.<name>.description`; and an entity-set description adds `summary`
(the same verb text as the matching MCP tool) plus `description` to every operation for that set
(`GET` collection and individual, `POST`, `PATCH`, `DELETE`). A set with no description keeps
today's output exactly — no `summary` or `description` key on its operations.

## Consuming `$oas2` from Power Automate

Power Automate (and Power Apps) can turn the document into a [custom connector](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-openapi-definition). It accepts OpenAPI **2.0 only** (not 3.0), which is exactly what OdataDuty emits, and the document must be **under 1 MB**. The rendered size grows with your schema (entity types, properties, enums), so a very large schema could approach that limit — check the byte size if you have hundreds of entities.

There are two ways to import, and they behave differently:

- **Import from OpenAPI file** — you download the `$oas2` JSON and upload it. This always works.
- **Import from URL** — you paste the `$oas2` URL. This is a **browser-side, cross-origin fetch** made from `make.powerautomate.com` / `make.powerapps.com`, so it is subject to [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS).

### The CORS requirement

Because "Import from URL" fetches from the browser, your server must return an `Access-Control-Allow-Origin` header on the `$oas2` response. Without it, the browser refuses to hand the response body to Power Automate and you get a **misleading error**:

> We weren't able to download the OpenAPI file from the provided URL. Please upload the file manually using the "Import from OpenAPI file" option.

This error is easy to misdiagnose: the request **reaches your server and returns `200`** (you will see it in your logs), so it looks like a download or content problem when it is really a missing CORS header. The generated Rails controller sets it for you:

```ruby
def oas2
  # Power Automate's "Import from URL" is a browser-side cross-origin fetch; without this CORS
  # header it fails with a misleading "couldn't download" error even though the server 200s.
  response.set_header('Access-Control-Allow-Origin', '*')
  render json: OdataDuty::OAS2.build_json(schema)
end
```

`*` is safe here: `$oas2` is public metadata fetched without credentials. If you prefer to scope it, allow the Power Platform origins instead:

```ruby
POWER_PLATFORM_ORIGINS = %w[
  https://make.powerapps.com
  https://make.powerautomate.com
  https://make.preview.powerapps.com
].freeze

def oas2
  origin = request.headers['Origin']
  if POWER_PLATFORM_ORIGINS.include?(origin)
    response.set_header('Access-Control-Allow-Origin', origin)
  end
  render json: OdataDuty::OAS2.build_json(schema)
end
```

A plain `GET` of `$oas2` is a CORS "simple request", so no `OPTIONS` preflight is sent — the response header above is all that is required. Add `Access-Control-Allow-Methods` / `Access-Control-Allow-Headers` only if you later expose the data endpoints to browser clients that trigger a preflight.

## Troubleshooting the "couldn't download" error

If Power Automate's "Import from URL" fails, work through it in this order — the failure is almost always transport, not the document:

1. **Does file import work?** Download the JSON and use "Import from OpenAPI file". If that succeeds, the document is valid and the problem is the fetch (keep going).
2. **Is the endpoint reachable anonymously?** `curl` it with no auth; you want `200 application/json`.
3. **Does the request reach your server?** Check your logs. A logged `200` with the import still failing points squarely at CORS.
4. **Is the CORS header present?** `curl -I -H 'Origin: https://make.powerapps.com' <url> | grep -i access-control` should echo an `Access-Control-Allow-Origin`.
