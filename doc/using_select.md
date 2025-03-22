# Using `$select` with OdataDuty

The `$select` query option in OData allows clients to request only a subset of properties from an entity. This reduces the payload size and improves performance by returning only the data you need.  
OdataDuty will call the `od_select` method on your entity set—if defined—to allow you to further optimize data loading and performance. Even if your `OdataDuty::EntitySet` does not implement `od_select`, OdataDuty will still return only the selected properties.

This guide explains how to implement `od_select` in your custom `OdataDuty::EntitySet` class.

## Overview

- **Purpose:** Return only the selected properties from your entities, reducing payload size and improving performance.
- **Mechanism:** When a `$select` query option is provided, OdataDuty parses it into an array of properties and passes that array to your `od_select` method.
- **Metadata:** Essential metadata (like `@odata.id`) is always included, regardless of the selection.

## Implementing `od_select`

To support `$select`, you implement the `od_select` method on your `OdataDuty::EntitySet` subclass. This method should:
- Accept an array of property names.
- Ensure that required properties (such as `id`) are always included.
- Filter your internal record collection to include only the specified properties.

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

  # Implements the $select logic.
  # Receives an array of property names (e.g., ['name', 'email'])
  def od_select(select)
    # Ensure that the 'id' property is always included
    columns = select.map(&:to_s)
    @records = @records.select(*columns)
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

### How It Works

1. **Parsing `$select`:**  
   When a client makes a request such as:  
   ```
   GET /MyEntitySet?$select=name,email
   ```  
   OdataDuty converts the `$select` value into an array like `[:id, :name, :email]`—always including the key property (`:id`).

2. **Invoking `od_select`:**  
   The framework calls your `od_select` method with the array. In the example above, it uses that array to select only the `name`, `email`, and `id` columns from the `@records` collection.

## Common Error Cases

While implementing `$select`, note the following error scenarios that your service should handle:

- **Unknown Property:**  
  If a property specified in `$select` does not exist on the entity, an `UnknownPropertyError` will be raised.

- **Nested Selection on Complex Types:**  
  Directly selecting nested properties (e.g., `c/s`) is not supported. This will result in an `InvalidQueryOptionError`.

- **Quoted Identifiers:**  
  Property names should not be enclosed in quotes. If quotes are detected, an `InvalidQueryOptionError` will be raised.

## Summary

- **Custom Entity Set:**  
  Subclass `OdataDuty::EntitySet` and implement the required methods (`od_after_init`, `collection`, `individual`), along with your custom `od_select`.

- **Implementing `od_select`:**  
  Update your internal records based on the array of selected properties—ensuring that mandatory keys like `id` are always included.

- **Usage:**  
  When clients pass a `$select` parameter, OdataDuty routes it to your `od_select` implementation to return a filtered response.

By following these guidelines, you'll provide robust support for the `$select` option in your OData API.
