# OdataDuty

Easily expose you ruby application or rails models as a OData service.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'odata_duty'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install odata_duty

## Usage

### Key Features

- **Define Entities and Properties**: Easily define your OData entities and their properties using simple Ruby classes.
- **Handle Collections**: Manage collections of entities with support for filtering, paging, and counting.
- **Support for Complex Types and Enums**: Define and use complex types and enumerations within your entities.
- **Retrieve Individual Items**: Implement methods to fetch individual entities by their keys.
- **Schema Definition**: Organize and expose your OData entities using schemas.

#### Quick Example

Here's a quick example demonstrating how to define entities, manage collections, and handle individual items.

```ruby
require 'odata_duty'

# Define an entity type
class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'user_name', String, nullable: false
  property 'name', String
  property 'emails', [String], nullable: false
end

# Define a collection set
class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  ALL_RECORDS = [
    OpenStruct.new(id: '1', user_name: 'user1', name: 'User One', emails: ['user1@example.com']),
    OpenStruct.new(id: '2', user_name: 'user2', name: 'User Two', emails: ['user2@example.com'])
  ]

  def od_after_init
    @records = ALL_RECORDS
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end

# Define the schema
class SampleSchema < OdataDuty::Schema
  namespace 'SampleSpace'
  entity_sets [PeopleSet]
end

# Example usage
schema = SampleSchema.new
puts schema.execute('People')
puts schema.execute("People('1')")
```

## TODO

* add support for composite keys
* add support for descriptions

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/odata_duty.
