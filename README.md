# OdataDuty

**OdataDuty** is a Ruby gem that lets you define structured data and operations once using a simple DSL — and expose them seamlessly to analytics tools (like PowerBI), no-code platforms (like PowerAutomate), and AI systems (via JSON-RPC or the Model Context Protocol).

It’s designed around the principle of _"define once, serve everywhere"_: you model your entities, properties, filters, and behaviors in Ruby, and OdataDuty takes care of transforming that into formats and protocols your tools and agents understand.

---

## ✨ Why use OdataDuty?

- ✅ Define your data model and logic in plain Ruby
- ✅ Support schema-based APIs (OpenAPI/Swagger)
- ✅ Avoid repeating business logic in multiple layers or formats
- ✅ Build for humans and works with reporting tools, automation tools, and LLMs (WIP) simultaneously

---

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'odata_duty'
```

And then execute:

```bash
bundle install
```

Or install it manually:

```bash
gem install odata_duty
```

### Rails Integration

If you're using Rails, you can use the included generators to quickly set up OdataDuty:

1. Set up the basic OData API structure:
```bash
bin/rails generate odata_duty:install
```

2. Generate entity types and sets:
```bash
bin/rails generate odata_duty:entity_set Product name:string price:decimal category:string
```

See the [Entity Set Generator documentation](doc/entity_set_generator.md) for more details.

---

## Getting Started

> The gem assumes basic familiarity with OData concepts.  
> If you’re new, check out the [OData Crash Course](doc/odata_crash_course.md).

### 🔧 Key Features

- **Entity and property definition** using a simple DSL
- **Filtering, paging, and count support**
- **Complex types and enums**
- **Individual item retrieval and creation**
- **Schema introspection and OpenAPI generation**

---

## DSL Quick Example

```ruby
require 'odata_duty'

class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'user_name', String, nullable: false
  property 'name', String
  property 'emails', [String], nullable: false
end

class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = Person.active
  end

  def collection
    @records
  end

  def individual(id)
    @records.find(id)
  end

  def create(data)
    Person.create!(username: data.user_name, name: data.name, emails: data.emails)
  end
end

class SampleSchema < OdataDuty::Schema
  namespace 'SampleSpace'
  entity_sets [PeopleSet]
  base_url Rails.application.routes.url_helpers.api_root_url
end
```

---

## Rails Integration Example

You can quickly generate the boilerplate controller, routes and schema with:

```bash
bin/rails generate odata_duty:install
```

```ruby
# config/routes.rb
scope '/api' do
  root 'api#index'
  get '$metadata' => 'api#metadata'
  get '$oas2' => 'api#oas2'
  get '*url' => 'api#show'
  post '*url' => 'api#create'
end
```

```ruby
# app/controllers/api_controller.rb

def index
  render json: OdataDuty::EdmxSchema.index_hash(schema)
end

def metadata
  render xml: OdataDuty::EdmxSchema.metadata_xml(schema)
end

def oas2
  render json: OdataDuty::OAS2.build_json(schema)
end

def show
  render json: schema.execute(params[:url], context: self, query_options: query_options)
end

def create
  render json: schema.create(params[:url], context: self, query_options: query_options)
end

private

def query_options
  params.to_unsafe_hash.except('url', 'action', 'controller', 'format')
end

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

```ruby
# app/models/people_resolver.rb
class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = Person.all
  end

  def od_filter_eq(property_name, value)
    @records = @records.where(property_name.to_sym => value)
  end

  def od_filter_ne(property_name, value)
    @records = @records.where.not(property_name.to_sym => value)
  end

  def od_filter_gt(property_name, value)
    @records = @records.where("#{property_name} > ?", value)
  end

  def od_filter_lt(property_name, value)
    @records = @records.where("#{property_name} < ?", value)
  end

  def count
    @records.count
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end
```

---

## 📚 Further Documentation

- [OData Crash Course](doc/odata_crash_course.md)
- [MCP Crash Course](doc/mcp_crash_course.md)
- [Using `$select`](doc/using_select.md)

---

## TODO

- Add support for composite keys
- Add support for schema descriptions
- Extend protocol adapters (MCP tools, resource reading)

---

## Development

```bash
bin/setup     # Install dependencies
rake spec     # Run the test suite
bin/console   # Open interactive console
```

### Test Server

To run the test server with auto-restart:

```bash
bundle exec rerun -- bundle exec rackup spec/config.ru
```

For MCP debugging with the inspector:

```bash
npx @modelcontextprotocol/inspector@0.15.0 -e PORT=9292 bundle exec rackup spec/config.ru
```

To install this gem locally:

```bash
bundle exec rake install
```

To release a new version:

```bash
bundle exec rake release
```

---

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/NEXL-LTS/odata_duty-ruby](https://github.com/NEXL-LTS/odata_duty-ruby).

If you're interested in extending the DSL to support new protocols or tool integrations, open an issue or start a discussion — the architecture is designed for extensibility.

---
