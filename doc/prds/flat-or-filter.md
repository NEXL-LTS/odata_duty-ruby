# Flat-OR support for `$filter`

## Summary
Lets a gem consumer's OData clients combine `$filter` predicates with `or` (e.g. `$filter=status eq 'active' or status eq 'pending'`), not just the implicit `and` supported today. Consumers opt in by implementing a single new hook, `od_filter_or`, on their entity set or resolver.

## Goal / Problem
Today `$filter` only supports conjunction. Predicates are applied sequentially, each one narrowing the result set, so `a eq 1 and b eq 2` works naturally but there is no way to express "match any of these." OData clients that PowerBI, PowerAutomate, and ad-hoc consumers generate routinely emit `or` (especially "this value or that value" on a single column), and OdataDuty currently has no path to serve them.

**Current behavior:** `$filter=name eq 'Bob' or name eq 'Alice'` is parsed as if `or` were part of a value/term and produces wrong or empty results — there is no `or` code path.

**Expected behavior:** the same query returns the union of records matching either predicate, by routing all or'd predicates to a consumer-implemented `od_filter_or`.

## What it enables
- As a gem consumer, I can support `$filter=color eq 'red' or color eq 'blue'` by implementing one hook that receives both predicates and returns their union.
- As a gem consumer, I can mix operations within a single OR — `price lt 10 or rating gt 4` — because each predicate carries its own operation.
- As an OData client, I can discover from `$metadata` that a set supports OR filtering and that grouping/parentheses are not supported.
- **Scope limit:** an expression must be *all* `and` or *all* `or`. Mixing them (`a eq 1 and b eq 2 or c eq 3`) and parenthesized grouping are not supported and raise a clear error.

## External API

A new hook, `od_filter_or(predicates)`, on the entity set (class DSL) or resolver (builder DSL). The framework calls it **once** with every or'd predicate, because OR is a union over independent predicates rather than sequential narrowing. The existing `od_filter_eq` / `od_filter_<prop>_<op>` hooks are unchanged and continue to handle the `and`/single-predicate path.

Each element of `predicates` is a read-only `OdataDuty::FilterPredicate` value object exposing:
- `#property_name` → Symbol, the entity property being filtered.
- `#operation` → Symbol, one of `:eq :ne :gt :lt :ge :le`.
- `#value` → the value already coerced to the property's type (same coercion the `and` path applies).

The hook's job: narrow `@records` to the union of records satisfying any predicate. Return value is ignored (consistent with the existing filter hooks); `collection`/`individual` read from `@records`.

**Class-based DSL:**
```ruby
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = Person.active
  end

  def od_filter_eq(property_name, value)        # and / single — unchanged
    @records = @records.where(property_name => value)
  end

  def od_filter_or(predicates)                  # new — all or'd predicates at once
    @records = predicates
      .map { |p| @records.where(p.property_name => p.value) }
      .reduce(:or)
  end

  def collection = @records
  def individual(id) = @records.find(id)
end
```

**Builder DSL (resolver):**
```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = Person.all
  end

  def od_filter_eq(property_name, value)
    @records = @records.where(property_name => value)
  end

  def od_filter_or(predicates)
    clauses = predicates.map do |p|
      case p.operation
      when :eq then @records.where(p.property_name => p.value)
      when :ne then @records.where.not(p.property_name => p.value)
      when :gt then @records.where("#{p.property_name} > ?", p.value)
      when :ge then @records.where("#{p.property_name} >= ?", p.value)
      when :lt then @records.where("#{p.property_name} < ?", p.value)
      when :le then @records.where("#{p.property_name} <= ?", p.value)
      else
        raise ArgumentError, "Unsupported filter operation: #{p.operation.inspect}"
      end
    end
    @records = clauses.reduce(:or)
  end
end
```

**Generated ActiveRecord concern:** the `odata_duty:entity_set` generator's concern ships a default `od_filter_or` that builds a union across the operations it already supports (`eq, ne, gt, lt, ge, le`), so freshly generated sets serve OR queries with no extra code.

## Behavior & expected I/O

Given a `People` set with records `Alice` (active), `Bob` (pending), `Carol` (archived):

**Request**
```
GET /People?$filter=status eq 'active' or status eq 'pending'
```
**Response** — union of both predicates:
```json
{ "value": [ { "id": "1", "name": "Alice", "status": "active" },
             { "id": "2", "name": "Bob",   "status": "pending" } ] }
```

**Mixed operations under OR**
```
GET /People?$filter=name eq 'Alice' or id gt 2
```
→ `od_filter_or` receives `[FilterPredicate(name, :eq, "Alice"), FilterPredicate(id, :gt, 2)]`.

**`and` path (unchanged)**
```
GET /People?$filter=status eq 'active' and name eq 'Alice'
```
→ still dispatches sequentially to `od_filter_eq`; `od_filter_or` is not called.

**`$metadata`** — mirroring the `$search` precedent, a set advertises filter capability (the exact `FilterRestrictions` properties for OR support / grouping constraints are TBD; see Open questions):
```xml
<EntitySet Name="People" EntityType="MySpace.PersonEntity">
  <Annotation Term="Capabilities.FilterRestrictions">
    <Record>
      <PropertyValue Property="Filterable" Bool="true" />
      <PropertyValue Property="NonFilterableProperties" />
    </Record>
  </Annotation>
</EntitySet>
```

**`$oas2`** — no schema change; `$filter` remains a freeform string parameter (its description is updated to mention OR).

## Common error cases
- **Mixed AND/OR** (`a eq 1 and b eq 2 or c eq 3`) → `NotYetSupportedError` ("mixed AND/OR not supported"), consistent with the `$search` restriction.
- **Parentheses / grouping** (`(a eq 1 or b eq 2) and c eq 3`) → `NotYetSupportedError` (existing parenthesis rejection).
- **OR used but no `od_filter_or` implemented** → `NoImplementationError` ("OR filtering not supported"), mirroring the `and`-path message.
- **Unknown property** in any predicate → `UnknownPropertyError` (unchanged).
- **OR applied to a collection property** → `InvalidQueryOptionError` (same validation as the `and` path).
- **Uncoercible value** for a property type → existing value-coercion error.

## Scope
**In:** flat single-operator OR for `$filter`; new `od_filter_or` hook in both the class-based and builder DSLs; `FilterPredicate` public value object; coercion + property validation reused for OR predicates; `$metadata` `FilterRestrictions` annotation; generator default `od_filter_or`; both spec trees (`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`).

**Out (future work):** nested/parenthesized grouping; mixed AND/OR precedence; the full expression-tree alternative (a single `od_filter(expression)` hook replacing the per-operation hooks); new `$filter` operators or functions (`contains`, etc.).

## Documentation impact
Add a new guide `doc/using_filter.md` in the style of `doc/using_search.md` (overview → `od_filter_*`/`od_filter_or` contract → syntax examples → "Common Error Cases" → "$metadata Integration"), and mention OR support in `README.md`. Guide to be written only on request.

## Open questions
- Exact `Capabilities.FilterRestrictions` term/property used to signal "grouping unsupported" — `FilterRestrictions` has no direct `UnsupportedExpressions/group` analog to `SearchRestrictions`; the builder should pick the closest standard property (likely `FilterExpressionRestrictions`) at implementation time.
