# Using `$filter` with OdataDuty

The `$filter` query option in OData allows clients to narrow a collection to entities whose properties satisfy one or more comparison predicates. Each predicate has the form `<property> <operation> <value>`, and predicates can be combined with `and` or `or`.

OdataDuty parses the `$filter` expression and dispatches each predicate to hook methods on your entity set or resolver—`od_filter_<operation>`, an optional property-specific `od_filter_<property>_<operation>`, and `od_filter_or` for OR expressions—so you can translate the comparison into whatever your data store understands.

This guide explains how to implement those hooks in your custom `OdataDuty::EntitySet` class. The same parsing and dispatch serves both DSLs, so the equivalent hooks work on an `OdataDuty::SetResolver` subclass when you use the builder DSL.

## Overview

- **Purpose:** Filter a collection to entities matching one or more `<property> <operation> <value>` predicates.
- **Operations:** `eq` (equal), `ne` (not equal), `gt` (greater than), `ge` (greater than or equal), `lt` (less than), `le` (less than or equal), following OData naming conventions.
- **Mechanism:** When a `$filter` query option is provided, OdataDuty parses it into predicates, coerces each value to the property's declared type, and dispatches to your hooks.
- **AND vs OR:** Predicates joined by `and` (or a single predicate) are applied **sequentially**, each narrowing the result set. Predicates joined by `or` are passed **together** as a union to a single `od_filter_or` hook.
- **Scope limit:** An expression must be either **all `and`** or **all `or`**. Mixing them, and parenthesized grouping, are not supported.

## Implementing the filter hooks

### AND / single-predicate hooks

For an expression with a single predicate or several joined by `and`, OdataDuty walks the predicates in order and, for each one, dispatches to the first hook your set responds to:

1. A property-specific hook `od_filter_<property>_<operation>(value)` (e.g. `od_filter_name_eq(value)`), if defined.
2. Otherwise, a generic per-operation hook `od_filter_<operation>(property_name, value)` (e.g. `od_filter_eq(property_name, value)`).

If neither is implemented, the framework raises `NoImplementationError` (`"<property> <operation> not supported"`).

Because AND predicates are applied sequentially, each hook narrows `@records` further. The `value` argument is already coerced to the property's declared type.

### OR hook

When the expression uses `or`, OdataDuty calls a single hook, `od_filter_or(predicates)`, **once**, passing an array of every or'd predicate. OR is a union over independent predicates, not sequential narrowing, so your implementation should assign `@records` to the union of records satisfying any predicate.

Each element of `predicates` is a read-only `OdataDuty::FilterPredicate` value object exposing:

- `#property_name` → `Symbol` — the entity property.
- `#operation` → `Symbol`, one of `:eq :ne :gt :lt :le :ge`.
- `#value` → the value already coerced to the property's declared type (the same coercion the AND path applies).

The hook's return value is ignored; `collection`/`individual` read from `@records`.

### Example Implementation (class DSL)

Below is a sample implementation for an entity set that uses ActiveRecord:

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

### Example Implementation (builder DSL resolver)

With the builder DSL, the data logic lives on an `OdataDuty::SetResolver` subclass referenced by name. The hooks are identical in shape. Here `od_filter_or` handles every supported operation:

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
      when :gt then @records.where("#{@records.table_name}.#{p.property_name} > ?", p.value)
      when :ge then @records.where("#{@records.table_name}.#{p.property_name} >= ?", p.value)
      when :lt then @records.where("#{@records.table_name}.#{p.property_name} < ?", p.value)
      when :le then @records.where("#{@records.table_name}.#{p.property_name} <= ?", p.value)
      else
        raise ArgumentError, "Unsupported filter operation: #{p.operation.inspect}"
      end
    end
    @records = clauses.reduce(:or)
  end
end
```

### How It Works

Given People `Alice` (active), `Bob` (pending), and `Carol` (archived):

1. **Sequential AND.**
   ```
   GET /People?$filter=status eq 'active' and name eq 'Alice'
   ```
   OdataDuty dispatches each predicate to `od_filter_eq` in turn, narrowing `@records` first by `status` then by `name`. `od_filter_or` is **not** called. The result is `Alice`.

2. **Union OR.**
   ```
   GET /People?$filter=status eq 'active' or status eq 'pending'
   ```
   OdataDuty calls `od_filter_or` once with both predicates. Your hook returns the union: `Alice` and `Bob`.

3. **Mixed operations in OR, with coercion.**
   ```
   GET /People?$filter=name eq 'Alice' or id gt 2
   ```
   `od_filter_or` receives `[FilterPredicate(name, :eq, "Alice"), FilterPredicate(id, :gt, 2)]`. Note `id` has been coerced to the Integer `2`, matching the property's declared type.

## Filter Syntax Examples

### Operations

| Operation | Meaning | Example |
| --------- | ------------------------- | ----------------------- |
| `eq`      | equal                     | `status eq 'active'`    |
| `ne`      | not equal                 | `status ne 'archived'`  |
| `gt`      | greater than              | `id gt 2`               |
| `ge`      | greater than or equal     | `id ge 3`               |
| `lt`      | less than                 | `age lt 65`             |
| `le`      | less than or equal        | `age le 64`             |

### Combining predicates

- `status eq 'active'` — single predicate.
- `status eq 'active' and age gt 18` — all `and`, applied sequentially (narrowing).
- `status eq 'active' or status eq 'pending'` — all `or`, applied as a union.

### Quoting

String values are single-quoted: `name eq 'Alice'`. The keywords `or` and `and` appearing **inside** a quoted value are treated as part of the value, not as separators—`name eq 'rock or roll'` filters for the literal string `rock or roll`.

### All-AND or all-OR

An expression must be entirely `and` or entirely `or`. You cannot mix the two operators in a single expression, and parenthesized grouping is not supported (see Common Error Cases below).

## Common Error Cases

While implementing `$filter`, note the following error scenarios:

- **Mixed AND/OR:**
  Expressions like `a eq 1 and b eq 2 or c eq 3` raise `NotYetSupportedError` (`"mixed AND/OR not supported"`).

- **Parentheses / grouping:**
  Expressions like `(a eq 1 or b eq 2) and c eq 3` raise `NotYetSupportedError` (`"filtering does not support functions or Grouping Operators"`).

- **Arithmetic operators:**
  Using `add`, `sub`, `mul`, `div`, or `mod` raises `NotYetSupportedError` (`"filtering with arithmetic operators not supported"`).

- **OR without a hook:**
  Using `or` when your set does not implement `od_filter_or` raises `NoImplementationError` (`"OR filtering not supported"`).

- **Unsupported AND/single operation:**
  An `and` or single predicate whose operation has no matching hook raises `NoImplementationError` (`"<property> <operation> not supported"`).

- **Unknown property:**
  A predicate referencing a property that does not exist on the entity raises `UnknownPropertyError`.

- **Collection property:**
  Filtering on a collection-valued property raises `InvalidQueryOptionError`.

- **Uncoercible value:**
  A value that cannot be coerced to the property's declared type raises `InvalidFilterValue`.

## Combining with Other Query Options

`$filter` can be combined with other OData query options:

```
GET /People?$filter=status eq 'active'&$select=name,email
GET /People?$filter=status eq 'active' or status eq 'pending'&$top=10
```

## Summary

- **Custom Entity Set:**
  Subclass `OdataDuty::EntitySet` (or `OdataDuty::SetResolver` for the builder DSL) and implement the required methods (`od_after_init`, `collection`, `individual`), along with your filter hooks.

- **AND / single predicates:**
  Implement `od_filter_<operation>(property_name, value)`—or a property-specific `od_filter_<property>_<operation>(value)`—to narrow `@records` sequentially.

- **OR predicates:**
  Implement `od_filter_or(predicates)` to assign `@records` to the union of records satisfying any of the supplied `FilterPredicate` objects.

- **Coercion:**
  Each predicate value is coerced to the property's declared type before it reaches your hook.

- **Scope:**
  An expression must be all `and` or all `or`; mixing operators, grouping, arithmetic, and functions are not supported.

## $metadata Integration

When a set implements `od_filter_or`, OdataDuty emits a `Capabilities.FilterRestrictions` annotation on that entity set, advertising filter support and signalling that grouping and parentheses are unsupported:

```xml
<EntitySet Name="People" EntityType="MySpace.PersonEntity">
    <Annotation Term="Capabilities.FilterRestrictions">
        <Record>
            <PropertyValue Property="Filterable" Bool="true" />
            <PropertyValue Property="FilterExpressionRestrictions">
                <Collection>
                    <Record>
                        <PropertyValue Property="Property" PropertyPath="*" />
                        <PropertyValue Property="AllowedExpressions" EnumMember="Capabilities.FilterExpressionType/SingleValue" />
                    </Record>
                </Collection>
            </PropertyValue>
        </Record>
    </Annotation>
</EntitySet>
```

A set **without** `od_filter_or` does not get this annotation. In either case, `$oas2` keeps `$filter` as a freeform string parameter—there is no schema change in the OAS2/Swagger document.

The `od_filter_or` default ships in the generator's ActiveRecord concern, so entity sets produced by the `entity_set` generator serve OR filtering with no extra code.
