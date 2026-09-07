# Using `$top`, `$skip`, and server-driven paging with OdataDuty

OData offers two complementary ways to page through a collection:

- **Client-driven paging** with `$top` (return at most N entities) and `$skip` (skip the first N
  entities), which the client sets explicitly on each request.
- **Server-driven paging** with `$skiptoken`, an opaque continuation value the *server* hands back
  to the client via `@odata.nextLink` in the response, and the client echoes back unchanged on the
  next request to continue where it left off.

OdataDuty parses these query options and dispatches to hook methods on your entity set or
resolver—`od_top`, `od_skip`, and `od_skiptoken`—so you decide how to apply them to your data.
For server-driven paging, your `collection` method calls `od_next_link_skiptoken` to tell the
framework what `$skiptoken` value to embed in `@odata.nextLink` for the next page.

This guide explains how to implement those hooks in your custom `OdataDuty::EntitySet` class. The
same parsing and dispatch serves both DSLs, so the equivalent hooks work on an
`OdataDuty::SetResolver` subclass when you use the builder DSL.

## Overview

- **Purpose:** Let clients request a bounded slice of a collection (`$top`/`$skip`), and let the
  server advertise how to fetch the next slice of a large result set (`$skiptoken` /
  `@odata.nextLink`).
- **Mechanism:** When `$top`, `$skip`, or `$skiptoken` is supplied, OdataDuty calls the
  corresponding hook—`od_top(top)`, `od_skip(skip)`, `od_skiptoken(skiptoken)`—with the raw string
  value from the query string. Your hook narrows `@records` (or equivalent internal state)
  accordingly.
- **Validation:** `$top` and `$skip` values are validated as non-negative base-10 integers
  *before* your hook is even checked for. An invalid value raises `OdataDuty::InvalidQueryOptionError`
  immediately—your `od_top`/`od_skip` hook never sees a malformed value. `$skiptoken` is treated as
  an opaque token and is not validated as a number.
- **Not implemented:** If the entity set doesn't implement the hook for a query option the client
  supplied, OdataDuty raises `NoImplementationError`.
- **Server-driven paging:** Your `collection` method decides, each time it runs, whether there is
  more data beyond what it's returning. If so, it calls `od_next_link_skiptoken(value)` with the
  token for the *next* page. OdataDuty then adds `@odata.nextLink` to the response, which is the
  same request URL with `$skiptoken` set to that value—ready for the client to follow.
- **Reachable over MCP too:** `list_<Set>` advertises `odata_top`, `odata_skip`, and
  `odata_skiptoken` arguments—each one only when the matching hook exists—so an agent can page a
  collection through the MCP server as well as over REST. See *Paging over MCP* below.

## Implementing the hooks

### `od_top` / `od_skip`

Implement `od_top(top)` and `od_skip(skip)` on your `OdataDuty::EntitySet` (or `SetResolver`)
subclass. Each receives the query-option value as a `String` already confirmed to be a
non-negative base-10 integer (e.g. `'10'`, `'0'`)—convert it yourself with `.to_i`:

```ruby
def od_top(top)
  @top = top
end

def od_skip(skip)
  @skip = skip
end
```

Both hooks may be present at once, and OdataDuty dispatches whichever ones the request supplied in
the order `$top`/`$skip` appear on the query string—**not** a fixed order. If you apply each hook
directly to `@records` as it runs (e.g. `@records = @records.first(top.to_i)` right inside
`od_top`), the result depends on which query option the client happened to write first, which is
never what you want. Instead, just store the raw values as shown above, then combine them yourself,
in a fixed order, inside `collection` (see the full examples below)—OData's own evaluation order
applies `$skip` before `$top`.

### `od_skiptoken`

Implement `od_skiptoken(skiptoken)` to resume a previous server-driven page. `skiptoken` is
whatever opaque string value your own `od_next_link_skiptoken` call previously handed the
framework (see below)—commonly an offset, but it can be any string your `collection` method knows
how to interpret:

```ruby
def od_skiptoken(skiptoken)
  @skiptoken = skiptoken
end
```

Store the token rather than slicing `@records` here—your `collection` method (below) is what turns
it into an offset. If `od_skiptoken` itself narrows `@records`, and `collection` *also* indexes into
`@records` using the same token, the offset is applied twice and the page comes out wrong.

### `od_next_link_skiptoken` and `@odata.nextLink`

`od_next_link_skiptoken(value)` is not a hook you implement—it's a method the framework provides
that *you call*, from inside your own `collection` method, whenever there is more data beyond the
page you're about to return. Call it with the `$skiptoken` value that should be used to fetch the
next page:

```ruby
def collection
  offset = @skiptoken.to_i
  max_results = 50
  od_next_link_skiptoken(offset + max_results) if @records.count > offset + max_results
  @records[offset, max_results] || []
end
```

After `collection` returns, OdataDuty checks whether `od_next_link_skiptoken` was called during
this request. If so, it adds an `@odata.nextLink` field to the response: the current request's URL
and query options, with `$skiptoken` set to the value you passed. If your `collection` method never
calls it (because there's no more data), no `@odata.nextLink` is added and the client knows it has
reached the last page.

Because `@odata.nextLink` is derived from the *current* request's query options plus your new
`$skiptoken`, any other query options on the original request (such as `$filter` or `$top`) are
preserved on the link, so the client can follow it as-is to continue the same filtered/limited
query.

### Example Implementation (class DSL)

```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  MAX_PAGE_SIZE = 50

  def od_after_init
    @records = Person.active
  end

  def od_top(top)
    @top = top
  end

  def od_skip(skip)
    @skip = skip
  end

  def od_skiptoken(skiptoken)
    @skiptoken = skiptoken
  end

  def collection
    @records = @records[@skip.to_i..] || [] if @skip
    @records = @records.first(@top.to_i) if @top
    offset = @skiptoken.to_i
    od_next_link_skiptoken(offset + MAX_PAGE_SIZE) if @records.count > offset + MAX_PAGE_SIZE
    @records[offset, MAX_PAGE_SIZE] || []
  end

  def individual(id) = @records.find { |r| r.id == id }
end
```

### Example Implementation (builder DSL resolver)

With the builder DSL, the same hooks live on an `OdataDuty::SetResolver` subclass referenced by
name:

```ruby
class PeopleResolver < OdataDuty::SetResolver
  MAX_PAGE_SIZE = 50

  def od_after_init
    @records = Person.active.to_a
  end

  def od_top(top)
    @top = top
  end

  def od_skip(skip)
    @skip = skip
  end

  def od_skiptoken(skiptoken)
    @skiptoken = skiptoken
  end

  def collection
    @records = @records[@skip.to_i..] || [] if @skip
    @records = @records.first(@top.to_i) if @top
    offset = @skiptoken.to_i
    od_next_link_skiptoken(offset + MAX_PAGE_SIZE) if @records.count > offset + MAX_PAGE_SIZE
    @records[offset, MAX_PAGE_SIZE] || []
  end
end
```

### How It Works

Given a `LargeCollection` set of 102 records and a 50-record page size (as above):

1. **First page.**
   ```
   GET /LargeCollection
   ```
   `collection` returns the first 50 records. Because more remain, it calls
   `od_next_link_skiptoken(50)`, so the response includes:
   ```
   "@odata.nextLink": "http://localhost:3000/api/LargeCollection?%24skiptoken=50"
   ```

2. **Following the link.**
   ```
   GET /LargeCollection?$skiptoken=50
   ```
   `od_skiptoken('50')` records the offset (`@records` is still the full 102). `collection` returns
   records 51–100 and calls `od_next_link_skiptoken(100)`. Because this request's own query options
   already contain `$skiptoken=50`, and OdataDuty adds the new value alongside it rather than
   replacing it, the resulting `@odata.nextLink` carries both:
   ```
   "@odata.nextLink": "http://localhost:3000/api/LargeCollection?%24skiptoken=50&%24skiptoken=100"
   ```
   Following this link works as expected regardless—standard query-string parsing takes the last
   occurrence of a repeated parameter, which is `100`.

3. **Last page.**
   ```
   GET /LargeCollection?$skiptoken=100
   ```
   Only 2 records remain, which is not more than the page size, so `collection` returns them
   without calling `od_next_link_skiptoken`. The response has **no** `@odata.nextLink`, signalling
   the client has reached the end.

4. **Client-driven `$top` alongside server-driven paging.**
   ```
   GET /LargeCollection?$filter=id ne '1'&$top=100
   ```
   The filter narrows `@records` before `collection` runs; `od_top('100')` just records the value,
   and `collection` applies it—narrowing to 100 records—before slicing out the 50-record page. The
   generated `@odata.nextLink` preserves the original `$filter` and `$top` alongside the new
   `$skiptoken`:
   ```
   "@odata.nextLink": "http://localhost:3000/api/LargeCollection?%24filter=id+ne+%271%27&%24top=100&%24skiptoken=50"
   ```

## Common Error Cases

While implementing paging, note the following error scenarios:

- **Negative `$top`/`$skip`:**
  `$top=-1` or `$skip=-1` raises `InvalidQueryOptionError`
  (`"'$top' must be a non-negative integer, got '-1'"`, or `'$skip'` respectively).

- **Non-numeric `$top`/`$skip`:**
  `$top=abc` raises `InvalidQueryOptionError` (`"'$top' must be a non-negative integer, got 'abc'"`).

- **Non-integer (decimal) `$top`/`$skip`:**
  `$top=1.5` raises `InvalidQueryOptionError` (`"'$top' must be a non-negative integer, got '1.5'"`).

- **Empty `$top`/`$skip`:**
  `$top=` (empty string) raises `InvalidQueryOptionError`
  (`"'$top' must be a non-negative integer, got ''"`).

- **`$top=0` / `$skip=0` are valid:**
  Zero is a valid non-negative integer. `$top=0` calls `od_top('0')`—typically yielding an empty
  `value` array, depending on your implementation. `$skip=0` calls `od_skip('0')`, typically
  yielding the full collection.

- **Leading zeros are decimal, not octal:**
  `$top=010` is valid and parsed as base-10 `10` (not octal `8`); your hook receives the original
  string `'010'` unchanged, exactly as any other valid value.

- **Validation runs before the "not implemented" check:**
  An invalid `$top`/`$skip` raises `InvalidQueryOptionError` even on an entity set that does not
  implement `od_top`/`od_skip` at all—the value is checked before OdataDuty checks whether your set
  supports the option.

- **`$top`/`$skip`/`$skiptoken` not implemented:**
  If the client supplies `$top`, `$skip`, or `$skiptoken` (with a *valid* value, for `$top`/`$skip`)
  and your entity set does not implement the corresponding hook, OdataDuty raises
  `NoImplementationError` (`"$top not implemented for #{class}"`, `"$skip not implemented for
  #{class}"`, or `"$skiptoken not implemented for #{class}"`). This is a REST-only case: over MCP
  the corresponding `odata_*` argument is not advertised at all, so it cannot be passed.

- **`$skiptoken` is not validated as numeric:**
  Unlike `$top`/`$skip`, `$skiptoken` is an opaque token as far as OdataDuty is concerned—any string
  is passed through to `od_skiptoken` unchanged. It's up to your implementation to interpret (and
  reject, if necessary) its contents.

## Combining with Other Query Options

`$top`, `$skip`, and `$skiptoken` can be combined with other OData query options:

```
GET /People?$filter=status eq 'active'&$top=10
GET /People?$select=name,email&$skip=20&$top=10
```

## Paging over MCP

The same three hooks drive what the [MCP](using_mcp.md) `list_<Set>` tool advertises. `odata_top`
appears only when the set defines `od_top`, `odata_skip` only with `od_skip`, and `odata_skiptoken`
only with `od_skiptoken`—so an agent is never invited to page a set that cannot. `odata_skiptoken`
is a coined alias for OData's `$skiptoken`, following the same `odata_<option>` convention as the
other query-option arguments, and is translated back before execution.

That closes the server-driven loop for an agent: a `list_<Set>` call returns the collection JSON
including `@odata.nextLink`, and the agent takes that link's `$skiptoken` value and passes it as
`odata_skiptoken` on its next `list_<Set>` call—exactly what a REST client does by following the
URL. Continuing the 102-record `LargeCollection` example above:

```
list_LargeCollection {}
  -> {"value": [ …50 records… ],
      "@odata.nextLink": "http://localhost:3000/api/LargeCollection?%24skiptoken=50"}
list_LargeCollection {"odata_skiptoken": "50"}
  -> GET /LargeCollection?$skiptoken=50   (records 51–100, plus a nextLink carrying 100)
```

`odata_top` and `odata_skip` are advertised as integers with `"minimum": 0`, so the MCP SDK rejects
a negative value against the tool's input schema—returning a tool-error result whose text starts
`"Invalid arguments: "`—rather than letting it reach the `InvalidQueryOptionError` described under
*Common Error Cases*. The REST path is unchanged and still raises there.

## Summary

- **Custom Entity Set:**
  Subclass `OdataDuty::EntitySet` (or `OdataDuty::SetResolver` for the builder DSL) and implement
  the required methods (`od_after_init`, `collection`, `individual`), along with `od_top`,
  `od_skip`, and/or `od_skiptoken` as needed.

- **Client-driven paging:**
  Implement `od_top(top)`/`od_skip(skip)` to narrow your records by a validated, non-negative
  base-10 integer string.

- **Server-driven paging:**
  Implement `od_skiptoken(skiptoken)` to resume from an opaque continuation value, and call
  `od_next_link_skiptoken(value)` from within `collection` whenever more data remains, so OdataDuty
  can add `@odata.nextLink` to the response.

- **Validation:**
  `$top`/`$skip` must be non-negative base-10 integers or OdataDuty raises
  `InvalidQueryOptionError` before your hooks run. `$skiptoken` is an opaque string and is not
  validated.

- **Not implemented:**
  Supplying `$top`, `$skip`, or `$skiptoken` over REST against a set that doesn't implement the
  matching hook raises `NoImplementationError`. Over MCP the argument is simply not advertised.

- **MCP:**
  `list_<Set>` exposes `odata_top`/`odata_skip`/`odata_skiptoken`, each gated on its hook, so an
  agent can follow a `@odata.nextLink`'s `$skiptoken` value by passing it as `odata_skiptoken` —
  see [`doc/using_mcp.md`](using_mcp.md).
