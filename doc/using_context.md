# Using the request `context` with OdataDuty

Every resolver hook runs with access to a per-request **context** object, reachable as
`context` inside `od_after_init`, `collection`, `individual`, `create`, `update`, `delete`, and the
other `od_*` hooks. It bundles two things a hook usually needs: whatever caller-supplied object you
handed to `schema.execute` / `.create` / `.update` / `.delete` (e.g. a Rails controller), and a
handful of framework-provided helpers for building URLs, reading the query options, and memoizing
per-request work.

## Overview

- **Purpose:** give hooks a single, stable handle on the current request — the caller's context plus
  framework helpers — without threading arguments through every method.
- **Access:** call `context` inside any hook. There is no setup; the framework wraps your
  `context:` argument for you.
- **Delegation:** the wrapper is a delegator, so any method that isn't one of the members below is
  forwarded to your caller-supplied `context:` object. `context.current_user`,
  `context.visible_people`, etc. call straight through to it.
- **Members:** `od_full_url`, `query_options`, `base_url`, and `current` (documented below).
- **Convention:** `od_full_url` and `current` are names coined for this gem, following its `od_*` /
  helper convention — OData itself has no term for a URL-builder helper or a per-request memo.

## Members

| Member | Contract |
| --- | --- |
| *(any other method)* | Delegated to the caller-supplied `context:` object. The wrapper is a delegator, so `context.your_method(...)` calls your object. |
| `od_full_url(path, anchor: nil, **query_params)` | Returns a **`String`** (not a `URI`): the schema base URL + `/` + `path`, with `query_params` www-form-encoded after `?` and `anchor` appended as a `#` fragment. This is the same helper the framework uses to build `@odata.context` / `@odata.nextLink` control information. |
| `query_options` | The query options passed to `execute`, normalized to a plain `Hash`. Any `#to_h`-able hash-like object works (e.g. Rails' `params`). Carries the OData system query options under their spec spellings — `$filter`, `$top`, `$skip`, `$select`, `$search`, … |
| `base_url` | The schema's base URL, with no trailing `/`. |
| `current` | A per-request memo `Hash`, initially empty (`{}`). Stable within a request, so it is handy for memoizing work you don't want to repeat across hooks — `context.current['x'] ||= expensive`. |

## `od_full_url` examples

With a schema whose base is `https://example.org/odata` (host `example.org`, `https`, base path
`/odata`):

```ruby
context.od_full_url('People')                      # => "https://example.org/odata/People"
context.od_full_url('People', top: 5)              # => "https://example.org/odata/People?top=5"
context.od_full_url('$metadata', anchor: 'People') # => "https://example.org/odata/$metadata#People"
```

The return value is always a `String`, so you can concatenate or store it directly.

## Delegation and helpers in a hook

### Class DSL (`OdataDuty::EntitySet`)

The hooks live on the entity set. `context` delegates unknown methods to whatever you pass as
`context:`, and exposes the helpers alongside:

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = context.visible_people   # delegated to your context: object
  end

  def collection
    context.current['audit'] ||= context.od_full_url('People', from: 'audit')
    @records
  end
end

# `my_controller` is your context object; `params` is any #to_h-able query options.
schema.execute('People', context: my_controller, query_options: params)
```

### Builder DSL (`OdataDuty::SchemaBuilder`)

The builder DSL puts the same hooks on an `OdataDuty::SetResolver` subclass, referenced from the
entity set by its class name as a string via `resolver:`. `context` behaves identically:

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = context.visible_people   # delegated to your context: object
  end

  def collection
    context.current['audit'] ||= context.od_full_url('People', from: 'audit')
    @records
  end
end

schema = OdataDuty::SchemaBuilder.build(namespace: 'MyApi', host: 'example.org',
                                        scheme: 'https', base_path: '/odata') do |s|
  person_type = s.add_entity_type(name: 'Person') do |et|
    et.property_ref 'id', String
    et.property 'name', String
  end
  s.add_entity_set(name: 'People', entity_type: person_type, resolver: 'PeopleResolver')
end

schema.execute('People', context: my_controller, query_options: params)
```

## `query_options` is normalized to a plain `Hash`

You can hand `execute` a plain `Hash` or any hash-like object that responds to `#to_h` — a Rails
`ActionController::Parameters` instance, for example. Inside a hook, `context.query_options` always
reads back as a plain `Hash` with the OData system query options under their spec spellings:

```ruby
# `params` is any #to_h-able object, e.g. { '$top' => '1' } wrapped in a params class.
schema.execute('People', context: my_controller, query_options: params)

# inside a hook:
context.query_options                       # => { '$top' => '1' }
context.query_options.instance_of?(Hash)    # => true
```

## `current` is a per-request memo

`context.current` starts empty and is the same `Hash` throughout a single request, so it is a
natural place to cache work shared across hooks (for instance, a lookup computed in `od_after_init`
and reused in `collection`):

```ruby
def collection
  context.current['expensive'] ||= compute_once
  context.current['expensive']
end
```

Each `execute` / `create` / `update` / `delete` call gets a fresh, empty `current`; nothing leaks
between requests.

## Summary

- **`context`** is the per-request handle available in every resolver hook.
- **Unknown methods delegate** to the caller-supplied `context:` object (the wrapper is a
  delegator).
- **`od_full_url(path, anchor:, **query_params)`** returns a **`String`**: base URL + `/path`, plus
  a `?`-encoded query and `#anchor` — the same builder used for `@odata.context` / `@odata.nextLink`.
- **`query_options`** is the passed query options normalized to a plain `Hash` (any `#to_h`-able
  object works), keyed by OData spec spellings (`$filter`, `$top`, …).
- **`base_url`** is the schema base URL with no trailing `/`.
- **`current`** is a fresh-per-request memo `Hash` for caching work across hooks.
- **Both DSLs** expose `context` identically — on the `EntitySet` subclass (class DSL) or the
  `SetResolver` subclass (builder DSL).
- **`od_full_url` and `current`** are gem-coined names following the `od_*` / helper convention;
  OData defines no equivalent term.
