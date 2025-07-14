# Using `$search` with OdataDuty

The `$search` query option in OData allows clients to perform free-text searches across entity contents. This provides a flexible way to find entities that match search terms without requiring specific property-based filtering.  
OdataDuty will call the `od_search` method on your entity set—if defined—to allow you to implement custom search logic optimized for your data store. if your `OdataDuty::EntitySet` does not implement `od_search` it will raise an `InvalidQueryOptionError`.

This guide explains how to implement `od_search` in your custom `OdataDuty::EntitySet` class.

## Overview

- **Purpose:** Search across entity contents using free-text queries, providing flexible matching capabilities.
- **Mechanism:** When a `$search` query option is provided, OdataDuty parses the search expression and passes it to your `od_search` method.
- **Flexibility:** The exact matching criteria depend on your implementation, allowing for full-text search, partial matching, or other search strategies.

## Implementing `od_search`

To support `$search`, you implement the `od_search` method on your `OdataDuty::EntitySet` subclass. This method should:
- Accept a search expression string.
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
  # Receives a search expression string (e.g., 'Boise')
  def od_search(search_expression)
    # Perform a case-insensitive search across multiple columns
    @records = @records.where(
      "LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR LOWER(address) LIKE ?",
      "%#{search_expression.downcase}%",
      "%#{search_expression.downcase}%",
      "%#{search_expression.downcase}%"
    )
  end

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
   GET /MyEntitySet?$search=Boise
   ```  
   OdataDuty extracts the search expression `"Boise"` and passes it to your `od_search` method.

2. **Invoking `od_search`:**  
   The framework calls your `od_search` method with the search expression. In the example above, it searches across the `name`, `email`, and `address` columns for entities containing "Boise".

3. **Flexible Matching:**  
   Unlike `$filter`, `$search` allows for implementation-specific matching logic. You can implement exact matching, partial matching, full-text search, or other search strategies based on your needs.

## Common Error Cases

While implementing `$search`, note the following error scenarios that your service should handle:

- **Invalid Search Expression:**  
  If the search expression contains invalid characters or syntax, an `InvalidQueryOptionError` should be raised.

- **Search Not Supported:**  
  If your entity set doesn't implement `od_search`, the framework may return an error or perform a default search implementation.

- **Performance Considerations:**  
  Large datasets may require indexing or optimized search implementations to maintain acceptable response times.

## Combining with Other Query Options

`$search` can be combined with other OData query options:

```
GET /MyEntitySet?$search=Boise&$select=name,email
GET /MyEntitySet?$search=John&$top=10
GET /MyEntitySet?$search=developer&$orderby=name
```

When combined with `$filter`, both conditions must be satisfied:

```
GET /MyEntitySet?$search=Boise&$filter=age gt 25
```

## Summary

- **Custom Entity Set:**  
  Subclass `OdataDuty::EntitySet` and implement the required methods (`od_after_init`, `collection`, `individual`), along with your custom `od_search`.

- **Implementing `od_search`:**  
  Filter your internal records based on the search expression—the exact matching logic is implementation-specific and can range from simple text matching to sophisticated full-text search.

- **Usage:**  
  When clients pass a `$search` parameter, OdataDuty routes it to your `od_search` implementation to return filtered results.

- **Flexibility:**  
  Unlike the strict comparison logic of `$filter`, `$search` allows for flexible, implementation-defined matching strategies.

By following these guidelines, you'll provide robust support for the `$search` option in your OData API, enabling powerful search capabilities for your clients.