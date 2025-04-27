# Using `init_args` with OdataDuty Resolvers

OdataDuty allows you to pass additional arguments to your resolver classes when they are initialized. This feature enables you to reuse the same resolver class in different entity sets while customizing its behavior based on the specific use case.

## Overview

- **Purpose:** Reuse resolver logic across multiple entity sets with different configurations.
- **Mechanism:** Pass `init_args` when defining an entity set, which are forwarded to the resolver's `od_after_init` method.
- **Benefits:** Reduces code duplication and promotes DRY (Don't Repeat Yourself) principles in your API design.

## How It Works

1. When defining an entity set with `add_entity_set`, you can include an optional `init_args` parameter.
2. These arguments are passed to the resolver's `od_after_init` method during initialization.
3. The resolver can use these arguments to customize its behavior for that specific entity set.

### Supported Argument Types

OdataDuty supports passing arguments to `od_after_init` in multiple formats:

- **Keyword arguments:** Pass a hash to `init_args` to use keyword arguments
- **Positional arguments:** Pass a single value or an array of values to `init_args` to use positional arguments

## Examples

### Example 1: Filtering Records by Status

A common use case is having multiple endpoints that serve different filtered views of the same data:

```ruby
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init(status: :any)
    @status = status
    @records = Person.all
    @records = @records.where(status: @status) unless @status == :any
  end

  def collection
    @records
  end

  def count
    @records.count
  end
  
  def individual(id)
    @records.find_by(id: id)
  end
end

# In your schema definition:
SchemaBuilder.build(namespace: 'MyApi', host: 'example.com') do |s|
  person_type = s.add_entity_type(name: 'Person') do |et|
    et.property_ref 'id', Integer
    et.property 'name', String
    et.property 'email', String
    et.property 'status', String
  end

  # Create multiple entity sets using the same resolver with different arguments
  s.add_entity_set(name: 'AllPeople', entity_type: person_type, 
                  resolver: 'PeopleResolver')
                  
  s.add_entity_set(name: 'ActivePeople', entity_type: person_type, 
                  resolver: 'PeopleResolver',
                  init_args: { status: :active })
                  
  s.add_entity_set(name: 'InactivePeople', entity_type: person_type, 
                  resolver: 'PeopleResolver',
                  init_args: { status: :inactive })
end
```

### Example 2: Using Positional Arguments

For simpler cases, you can use positional arguments:

```ruby
class CategoryResolver < OdataDuty::SetResolver
  def od_after_init(category = 'general')
    @category = category
    @records = Product.where(category: @category)
  end
  
  def collection
    @records
  end
  
  def individual(id)
    @records.find_by(id: id)
  end
end

# In your schema definition:
s.add_entity_set(name: 'GeneralProducts', entity_type: product_type, 
                resolver: 'CategoryResolver')
                
s.add_entity_set(name: 'ElectronicsProducts', entity_type: product_type, 
                resolver: 'CategoryResolver',
                init_args: 'electronics')

# You can also pass an array for multiple positional arguments
s.add_entity_set(name: 'FilteredProducts', entity_type: product_type, 
                resolver: 'FilteredCategoryResolver',
                init_args: ['electronics', 'in_stock'])
```

## Best Practices

1. **Default Values:** Always provide default values for your `od_after_init` parameters to make them optional.
2. **Error Handling:** Handle missing or invalid arguments gracefully inside your resolver.
3. **Documentation:** Document the expected arguments for each resolver to make your code more maintainable.
4. **Type Checking:** Validate incoming arguments to ensure they are of the expected type.

## Error Handling

If there's a mismatch between the arguments expected by `od_after_init` and what's provided via `init_args`, OdataDuty will raise an `InitArgsMismatchError`. This helps catch configuration errors early.

## Summary

- Use `init_args` to customize resolver behavior without creating multiple similar resolver classes.
- Works with both keyword arguments and positional arguments.
- Promotes code reuse and separation of concerns in your API implementation.
- Enables creating multiple distinct endpoints from the same underlying resolver code.

By leveraging `init_args`, you can create more flexible and maintainable OData services with OdataDuty.