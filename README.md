# OdataDuty

Write OData compatible APIs in Ruby with the goal of easily connection your application to Microsoft PowerBI and PowerAutomate.

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

#### Quick Dynamic Example with Rails

```ruby
# add to routes.rb

scope '/api' do
  root 'api#index'
  get '$metadata' => 'api#metadata', as: 'metadata'
  get '$oas2' => 'api#oas2', as: 'oas2'
  get '*url' => 'api#show', as: 'show'
end
```

```ruby
# add to api_controller.rb
def index # OData Service Index
  render json: OdataDuty::EdmxSchema.index_hash(schema)
end

def metadata # OData metadata
  render xml: OdataDuty::EdmxSchema.metadata_xml(schema)
end

def oas2 # OpenAPI 2.0 (Swagger) schema
  render xml: OdataDuty::OAS2.build_json(schema)
end

def show
  query_options = params.to_unsafe_hash.except('url', 'action', 'controller', 'format')
  render json: schema.execute(params[:url], context: self, query_options: query_options)
end

private

def schema
  @schema ||= OdataDuty::SchemaBuilder.build(namespace: 'MySpace', host: request.host_with_port,
                                          scheme: request.scheme, base_path: api_index_path) do |s|
    s.title = "My Dynamic API"
    s.version = '0.0.1'
    person_entity = s.add_entity_type(name: 'Person') do |et|
      et.property_ref 'id', String
      et.property 'user_name', String, nullable: false
    end
    s.add_entity_set(url: 'People', entity_type: person_entity,
                      resolver: 'PeopleResolver')
  end
end
```

## TODO

* add support for composite keys
* add support for descriptions

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/odata_duty.
