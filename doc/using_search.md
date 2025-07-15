# Using `$search` with OdataDuty

The `$search` query option in OData allows clients to perform free-text searches across entity contents. This provides a flexible way to find entities that match search terms without requiring specific property-based filtering.  
OdataDuty will call the `od_search` method on your entity set—if defined—to allow you to implement custom search logic optimized for your data store. if your `OdataDuty::EntitySet` does not implement `od_search` it will raise an `InvalidQueryOptionError`.

This guide explains how to implement `od_search` in your custom `OdataDuty::EntitySet` class.

## Overview

- **Purpose:** Search across entity contents using structured search expressions with support for AND, OR, and NOT operators.
- **Mechanism:** When a `$search` query option is provided, OdataDuty parses the search expression into a `SearchExpression` object and passes it to your `od_search` method.
- **Operators:** Supports AND (explicit or implicit), OR, and NOT operators following OData v4.01 specification.
- **Flexibility:** The exact matching criteria depend on your implementation, allowing for full-text search, partial matching, or other search strategies.

## Implementing `od_search`

To support `$search`, you implement the `od_search` method on your `OdataDuty::EntitySet` subclass. This method should:
- Accept a `SearchExpression` object containing parsed terms and operators.
- Handle AND, OR, and NOT operators according to your search strategy.
- Filter your internal record collection to include only entities matching the search criteria.
- Return the filtered collection for further processing.

### Example Implementation

Below is a sample implementation for an entity set that uses ActiveRecord:

```ruby
class MyCustomEntitySet < OdataDuty::EntitySet
  # Associate the entity type with this set
  entity_type MyEntity

  def od_after_init
    # Assume People.active returns an ActiveRecord collection
    @records = People.active
  end

  # Implements the $search logic.
  # Receives a SearchExpression object with parsed terms and operators
  def od_search(search_expression)
    if search_expression.or?
      # Handle OR expressions: find records matching any term
      found_records = []
      search_expression.terms.each do |term|
        condition = build_search_condition(term)
        matches = @records.where(condition)
        found_records += matches
      end
      @records = found_records.uniq
    else
      # Handle AND expressions: apply each term sequentially
      search_expression.terms.each do |term|
        condition = build_search_condition(term)
        @records = @records.where(condition)
      end
    end
  end

  private

  def build_search_condition(term)
    # Build search condition based on whether term is negated
    search_pattern = "%#{term.value.downcase}%"
    base_condition = "LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR LOWER(address) LIKE ?"
    
    if term.not?
      # Negate the condition
      "NOT (#{base_condition})"
    else
      base_condition
    end
  end

  public

  # Return a collection of records
  def collection
    @records
  end

  # Return a single record based on its id
  def individual(id)
    collection.find(id)
  end
end
```

### Advanced Search Implementation

For more sophisticated search capabilities, you might implement full-text search:

```ruby
class MyCustomEntitySet < OdataDuty::EntitySet
  entity_type MyEntity

  def od_after_init
    @records = People.active
  end

  def od_search(search_expression)
    # Use PostgreSQL full-text search
    @records = @records.where(
      "to_tsvector('english', name || ' ' || email || ' ' || address) @@ plainto_tsquery('english', ?)",
      search_expression
    )
  end

  def collection
    @records
  end

  def individual(id)
    collection.find(id)
  end
end
```

### How It Works

1. **Parsing `$search`:**  
   When a client makes a request such as:  
   ```
   GET /MyEntitySet?$search=name AND NOT "old data"
   ```  
   OdataDuty parses the search expression into a `SearchExpression` object containing:
   - `terms`: Array of `SearchTerm` objects (e.g., `[{value: "name", negated: false}, {value: "old data", negated: true}]`)
   - `operator`: `:and` or `:or` indicating how terms should be combined

2. **Invoking `od_search`:**  
   The framework calls your `od_search` method with the parsed `SearchExpression`. Your implementation can:
   - Check `search_expression.or?` or `search_expression.and?` to determine the operator
   - Iterate through `search_expression.terms` to access each term
   - Use `term.not?` to check if a term is negated
   - Access `term.value` to get the actual search text

3. **Flexible Matching:**  
   Unlike `$filter`, `$search` allows for implementation-specific matching logic. You can implement exact matching, partial matching, full-text search, or other search strategies based on your needs.

## Search Syntax Examples

The `$search` query option supports the following syntax:

### Basic Terms
- `hello` - Single word search
- `"hello world"` - Quoted phrase search (exact phrase)

### Logical Operators
- `hello world` - Implicit AND (both terms must match)
- `hello AND world` - Explicit AND (both terms must match)
- `hello OR world` - OR operator (either term can match)
- `NOT hello` - Negation (must not contain "hello")

### Complex Expressions
- `hello AND NOT world` - AND with negation
- `"exact phrase" OR word` - Quoted phrases with OR
- `term1 term2 term3` - Multiple terms with implicit AND

### Important Notes
- **Operator precedence:** NOT has higher precedence than AND/OR
- **Mixed operators:** You cannot mix AND and OR in the same expression (raises `NoImplementationError`)
- **Parentheses:** Not supported and will raise `NoImplementationError` 
- **Quoted phrases:** Use double quotes for exact phrase matching
- **Case sensitivity:** Search matching is implementation-dependent

## Common Error Cases

While implementing `$search`, note the following error scenarios that your service should handle:

- **Invalid Search Expression:**  
  If the search expression contains invalid characters or syntax, an `InvalidQueryOptionError` will be raised.

- **Mixed Operators:**  
  Expressions like `apple AND orange OR peach` will raise `NoImplementationError` because mixing AND/OR is not supported.

- **Parentheses:**  
  Expressions like `(apple OR orange) AND peach` will raise `NoImplementationError` because parentheses are not supported.

- **Search Not Supported:**  
  If your entity set doesn't implement `od_search`, the framework will raise `NoImplementationError`.

- **Performance Considerations:**  
  Large datasets may require indexing or optimized search implementations to maintain acceptable response times.

## Combining with Other Query Options

`$search` can be combined with other OData query options:

```
GET /MyEntitySet?$search="John Doe"&$select=name,email
GET /MyEntitySet?$search=manager OR developer&$top=10
GET /MyEntitySet?$search=active AND NOT archived&$orderby=name
```

When combined with `$filter`, both conditions must be satisfied:

```
GET /MyEntitySet?$search="senior developer" AND NOT intern&$filter=age gt 25
```

## Summary

- **Custom Entity Set:**  
  Subclass `OdataDuty::EntitySet` and implement the required methods (`od_after_init`, `collection`, `individual`), along with your custom `od_search`.

- **Implementing `od_search`:**  
  Handle `SearchExpression` objects containing parsed terms with AND, OR, and NOT operators. The exact matching logic is implementation-specific and can range from simple text matching to sophisticated full-text search.

- **Search Expression Structure:**  
  Access `search_expression.terms` for individual search terms, `search_expression.or?`/`search_expression.and?` for operator type, and `term.not?`/`term.value` for term details.

- **Usage:**  
  When clients pass a `$search` parameter, OdataDuty parses it into a structured expression and routes it to your `od_search` implementation to return filtered results.

- **Flexibility:**  
  Unlike the strict comparison logic of `$filter`, `$search` allows for flexible, implementation-defined matching strategies with support for complex boolean logic.

By following these guidelines, you'll provide robust support for the `$search` option in your OData API, enabling powerful search capabilities with AND, OR, and NOT operators for your clients.