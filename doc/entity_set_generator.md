# Using the OData Entity Set Generator

The OData Duty gem includes a Rails generator to help you quickly scaffold OData entity sets with proper structure and configuration.

## Basic Usage

Generate entity types and sets with a single command:

```bash
bin/rails generate odata_duty:entity_set ModelName field1:type field2:type field3:type
```

You can also generate namespaced entities:

```bash
bin/rails generate odata_duty:entity_set Namespace::ModelName field1:type field2:type field3:type
```

This will create a namespaced module structure and place files in the appropriate subdirectories.

This will create:
- `app/odata/model_name_entity.rb` (EntityType)
- `app/odata/model_name_set.rb` (EntitySet)
- Corresponding test files in `spec/odata/`

```ruby
# Example generated file: app/odata/model_name_entity.rb
class ModelNameEntity < OdataDuty::EntityType
  property_ref 'id', String, nullable: false
  property 'field1', String
  property 'field2', Integer
  property 'field3', Boolean
end
```

```ruby
# Example generated file: app/odata/model_name_set.rb
class ModelNameSet < OdataDuty::EntitySet
  include OdataActiveRecordConcern 
  entity_type ModelNameEntity

  def od_after_init
    @records = ModelName.active
  end

  def create(data)
    ModelName.create!(field1: data.field1, field2: data.field2, field3: data.field3)
  end

  def delete(id)
    record = @records.find_by(id: id)
    return nil unless record

    record.destroy!
    record
  end
end
```

The generated set scaffolds both a `create` method (making the set insertable) and a `delete(id)`
method (making it deletable). `delete` receives the coerced entity key, removes the matching record,
and returns a truthy value on success — returning falsey (when no record matches) makes OdataDuty
raise a `ResourceNotFoundError`. Delete what you don't need: removing the `delete` method drops the
set's `DELETE` support across `$oas2`, `$metadata`, and MCP. See
[Using `create`, `update`, and `delete`](using_create_update_and_delete.md) for the full write-operation
contract.

The companion `odata_duty:install` generator wires the matching Rails endpoints — a `destroy`
controller action that calls `schema.delete(...)` and responds `204 No Content`, plus a
`delete '*url' => 'api#destroy'` route alongside the `get`/`post` routes.

## Examples

Generate a Customer entity with id, name and email properties:

```bash
bin/rails generate odata_duty:entity_set Customer id:string name:string email:string
```

Generate an Order entity with order_number, date and amount properties, skipping test generation:

```bash
bin/rails generate odata_duty:entity_set Order order_number:string date:date amount:integer --skip-tests
```

Generate a namespaced entity:

```bash
bin/rails generate odata_duty:entity_set MySpace::Customer id:string name:string email:string
```

This will create:
- `app/odata/my_space/customer_entity.rb`
- `app/odata/my_space/customer_set.rb`
- Corresponding test files in `spec/odata/my_space/`

## Supported Data Types

The entity set generator supports the following data types:

| Ruby Type        | OData Type     |
|------------------|---------------|
| String           | Edm.String        |
| Integer          | Edm.Int64       |
| Date             | Edm.Date        |
| Time             | Edm.DateTimeOffset       |
| TrueClass        | Edm.Boolean   |


## ActiveRecord Integration

The generator automatically creates an `OdataActiveRecordConcern` module in `app/odata/odata_active_record_concern.rb` that is included in all generated entity sets. This concern provides integration with ActiveRecord models and implements OData protocol features like:

- Filtering with `$filter` (eq, ne, gt, lt, ge, le operators)
- Pagination with `$top`, `$skip`, and `$skiptoken`
- Automatic handling of large result sets


## Next Steps

After generating the files, you'll need to:

1. Update the entity set class with your specific data access logic if needed
2. Add the EntitySet to your OData schema

```ruby
# Example of what the updated: app/odata/app_schema.rb
class AppSchema < OdataDuty::Schema
  namespace 'AppSchema'
  entity_sets [ModelNameSet] # include entity set in here
  base_url Rails.application.routes.url_helpers.api_root_url
end
```
