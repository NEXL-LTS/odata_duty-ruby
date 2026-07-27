require 'spec_helper'

class FilterValidationEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class FilterValidationSet < OdataDuty::EntitySet
  entity_type FilterValidationEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a')]
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterValidationSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterValidationSet]
end

RSpec.describe OdataDuty::EntitySet, 'filter validation errors' do
  subject(:schema) { FilterValidationSchema }

  def execute(filter)
    schema.execute('FilterValidation', context: Context.new,
                                       query_options: { '$filter' => filter })
  end

  it 'rejects arithmetic operators' do
    expect { execute('id add 1 eq 2') }
      .to raise_error(OdataDuty::NotYetSupportedError, /arithmetic operators/)
  end

  %w[add sub mul div mod].each do |operator|
    it "rejects the #{operator} arithmetic operator" do
      expect { execute("id #{operator} 1 eq 2") }
        .to raise_error(OdataDuty::NotYetSupportedError,
                        'filtering with arithmetic operators not supported')
    end
  end

  it 'rejects grouping operators and functions with a descriptive message' do
    expect { execute("(name eq 'a')") }
      .to raise_error(OdataDuty::NotYetSupportedError,
                      'filtering does not support functions or Grouping Operators')
  end

  it 'rejects nested property filtering' do
    expect { execute('address/city eq \'x\'') }
      .to raise_error(OdataDuty::NotYetSupportedError, /nested property filtering/)
  end

  it 'raises UnknownPropertyError naming the undeclared property, without quotes' do
    expect { execute("bogus eq 'x'") }
      .to raise_error(OdataDuty::UnknownPropertyError, 'No such property bogus')
  end

  it 'filters a declared non-collection property without raising' do
    json = execute("name eq 'a'")
    expect(Oj.load(json)['value'].map { |v| v['name'] }).to contain_exactly('a')
  end
end

class FilterCoercionFailureEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'count', Integer
end

class FilterCoercionFailureSet < OdataDuty::EntitySet
  entity_type FilterCoercionFailureEntity

  def od_after_init
    @records = []
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterCoercionFailureSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterCoercionFailureSet]
end

RSpec.describe OdataDuty::EntitySet, 'filter value that fails type coercion' do
  subject(:schema) { FilterCoercionFailureSchema }

  it 'raises InvalidFilterValue naming the bad value and the property' do
    expect do
      schema.execute('FilterCoercionFailure', context: Context.new,
                                              query_options: { '$filter' => 'count eq abc' })
    end.to raise_error(OdataDuty::InvalidFilterValue, 'Invalid value abc for count')
  end
end

class FilterCollectionEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'tags', [String]
end

class FilterCollectionSet < OdataDuty::EntitySet
  entity_type FilterCollectionEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', tags: ['x'])]
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name).include?(value) }
  end

  def collection
    @records
  end
end

class FilterCollectionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterCollectionSet]
end

RSpec.describe OdataDuty::EntitySet, 'filtering a collection property' do
  subject(:schema) { FilterCollectionSchema }

  it 'raises InvalidQueryOptionError naming the operation and property' do
    expect do
      schema.execute('FilterCollection', context: Context.new,
                                         query_options: { '$filter' => "tags eq 'x'" })
    end.to raise_error(OdataDuty::InvalidQueryOptionError,
                       "Cannot apply 'eq' to a collection property 'tags'.")
  end
end

module FilterContextType
  def self.scalar? = true
  def self.property_type = 'Edm.String'
  def self.to_oas2(is_collection:) = is_collection ? { 'type' => 'array' } : { 'type' => 'string' }

  def self.to_value(value, context)
    return value if value.nil?

    "#{context.current.class}:#{value}"
  end
end

module FilterContextCapture
  module_function

  def value = @value

  def value=(val)
    @value = val
  end
end

class FilterContextEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'code', FilterContextType
end

class FilterContextSet < OdataDuty::EntitySet
  entity_type FilterContextEntity

  def od_after_init
    @records = []
  end

  def od_filter_eq(_property_name, value)
    FilterContextCapture.value = value
    @records = []
  end

  def collection
    @records
  end
end

class FilterContextSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterContextSet]
end

RSpec.describe OdataDuty::EntitySet, 'filter value coercion via the request context' do
  subject(:schema) { FilterContextSchema }

  it 'coerces the filter value through the property using the request context' do
    schema.execute('FilterContext', context: Context.new,
                                    query_options: { '$filter' => "code eq 'x'" })
    expect(FilterContextCapture.value).to eq('Hash:x')
  end

  it 'passes a quoted literal containing a comma through as a single value' do
    schema.execute('FilterContext', context: Context.new,
                                    query_options: { '$filter' => "code eq 'Smith, John'" })
    expect(FilterContextCapture.value).to eq('Hash:Smith, John')
  end
end

module FilterDispatchCapture
  module_function

  def calls
    @calls ||= []
  end

  def reset
    @calls = []
  end
end

class FilterDispatchEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'status', String
end

class FilterSpecificDispatchSet < OdataDuty::EntitySet
  entity_type FilterDispatchEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a', status: 'active')]
  end

  def od_filter_name_eq(value)
    FilterDispatchCapture.calls << [:specific, value]
    @records = @records.select { |r| r.name == value }
  end

  def od_filter_eq(property_name, value)
    FilterDispatchCapture.calls << [:generic, property_name, value]
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterGenericOnlyDispatchSet < OdataDuty::EntitySet
  entity_type FilterDispatchEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a', status: 'active')]
  end

  def od_filter_eq(property_name, value)
    FilterDispatchCapture.calls << [:generic, property_name, value]
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterNoHookDispatchSet < OdataDuty::EntitySet
  entity_type FilterDispatchEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a', status: 'active')]
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterDispatchSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterSpecificDispatchSet, FilterGenericOnlyDispatchSet, FilterNoHookDispatchSet]
end

RSpec.describe OdataDuty::EntitySet, 'od_filter_* hook dispatch' do
  subject(:schema) { FilterDispatchSchema }

  before { FilterDispatchCapture.reset }

  it 'prefers the property-specific hook when one exists' do
    schema.execute('FilterSpecificDispatch', context: Context.new,
                                             query_options: { '$filter' => "name eq 'a'" })
    expect(FilterDispatchCapture.calls).to eq([[:specific, 'a']])
  end

  it 'falls back to the generic hook with property_name and value' do
    schema.execute('FilterGenericOnlyDispatch', context: Context.new,
                                                query_options: { '$filter' => "name eq 'a'" })
    expect(FilterDispatchCapture.calls).to eq([[:generic, :name, 'a']])
  end

  it 'raises NoImplementationError naming the property and operation' do
    expect do
      schema.execute('FilterNoHookDispatch', context: Context.new,
                                             query_options: { '$filter' => 'name gt \'a\'' })
    end.to raise_error(OdataDuty::NoImplementationError, 'name gt not supported')
  end
end
