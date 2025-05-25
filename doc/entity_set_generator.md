# Using the OData Entity Set Generator

The OData Duty gem includes a Rails generator to help you quickly scaffold OData entity sets with proper structure and configuration.

## Basic Usage

Generate entity types and sets with a single command:

```bash
bin/rails generate odata_duty:entity_set ModelName field1:type field2:type field3:type
```

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
end
```

## Examples

Generate a Customer entity with id, name and email properties:

```bash
bin/rails generate odata_duty:entity_set Customer id:string name:string email:string
```

Generate an Order entity with order_number, date and amount properties, skipping test generation:

```bash
bin/rails generate odata_duty:entity_set Order order_number:string date:date amount:integer --skip-tests
```

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
