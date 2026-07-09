require 'spec_helper'

class BuilderFilterValidationResolver < OdataDuty::SetResolver
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

class BuilderFilterCollectionResolver < OdataDuty::SetResolver
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

module BuilderFilterContextType
  def self.scalar? = true
  def self.property_type = 'Edm.String'
  def self.to_oas2(is_collection:) = is_collection ? { 'type' => 'array' } : { 'type' => 'string' }

  def self.to_value(value, context)
    return value if value.nil?

    "#{context.current.class}:#{value}"
  end
end

module BuilderFilterContextCapture
  module_function

  def value = @value

  def value=(val)
    @value = val
  end
end

class BuilderFilterContextResolver < OdataDuty::SetResolver
  def od_after_init
    @records = []
  end

  def od_filter_eq(_property_name, value)
    BuilderFilterContextCapture.value = value
    @records = []
  end

  def collection
    @records
  end
end

module BuilderFilterDispatchCapture
  module_function

  def calls
    @calls ||= []
  end

  def reset
    @calls = []
  end
end

class BuilderFilterSpecificDispatchResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a', status: 'active')]
  end

  def od_filter_name_eq(value)
    BuilderFilterDispatchCapture.calls << [:specific, value]
    @records = @records.select { |r| r.name == value }
  end

  def od_filter_eq(property_name, value)
    BuilderFilterDispatchCapture.calls << [:generic, property_name, value]
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class BuilderFilterGenericOnlyDispatchResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a', status: 'active')]
  end

  def od_filter_eq(property_name, value)
    BuilderFilterDispatchCapture.calls << [:generic, property_name, value]
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class BuilderFilterNoHookDispatchResolver < OdataDuty::SetResolver
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

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, '$filter validation and dispatch' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        simple = s.add_entity_type(name: 'BuilderFilterValidation') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end
        s.add_entity_set(name: 'BuilderFilterValidation', entity_type: simple,
                         resolver: 'BuilderFilterValidationResolver')

        collection = s.add_entity_type(name: 'BuilderFilterCollection') do |et|
          et.property_ref 'id', String
          et.property 'tags', [String]
        end
        s.add_entity_set(name: 'BuilderFilterCollection', entity_type: collection,
                         resolver: 'BuilderFilterCollectionResolver')

        ctx = s.add_entity_type(name: 'BuilderFilterContext') do |et|
          et.property_ref 'id', String
          et.property 'code', BuilderFilterContextType
        end
        s.add_entity_set(name: 'BuilderFilterContext', entity_type: ctx,
                         resolver: 'BuilderFilterContextResolver')

        dispatch = s.add_entity_type(name: 'BuilderFilterDispatch') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'status', String
        end
        s.add_entity_set(name: 'BuilderFilterSpecificDispatch', entity_type: dispatch,
                         resolver: 'BuilderFilterSpecificDispatchResolver')
        s.add_entity_set(name: 'BuilderFilterGenericOnlyDispatch', entity_type: dispatch,
                         resolver: 'BuilderFilterGenericOnlyDispatchResolver')
        s.add_entity_set(name: 'BuilderFilterNoHookDispatch', entity_type: dispatch,
                         resolver: 'BuilderFilterNoHookDispatchResolver')
      end
    end

    before { BuilderFilterDispatchCapture.reset }

    def execute(entity_set, filter)
      schema.execute(entity_set, context: Context.new, query_options: { '$filter' => filter })
    end

    it 'raises UnknownPropertyError naming the undeclared property, without quotes' do
      expect { execute('BuilderFilterValidation', "bogus eq 'x'") }
        .to raise_error(OdataDuty::UnknownPropertyError, 'No such property bogus')
    end

    it 'filters a declared non-collection property without raising' do
      json = execute('BuilderFilterValidation', "name eq 'a'")
      expect(Oj.load(json)['value'].map { |v| v['name'] }).to contain_exactly('a')
    end

    it 'raises InvalidQueryOptionError naming the operation and collection property' do
      expect { execute('BuilderFilterCollection', "tags eq 'x'") }
        .to raise_error(OdataDuty::InvalidQueryOptionError,
                        "Cannot apply 'eq' to a collection property 'tags'.")
    end

    it 'coerces the filter value through the property using the request context' do
      execute('BuilderFilterContext', "code eq 'x'")
      expect(BuilderFilterContextCapture.value).to eq('Hash:x')
    end

    it 'prefers the property-specific hook when one exists' do
      execute('BuilderFilterSpecificDispatch', "name eq 'a'")
      expect(BuilderFilterDispatchCapture.calls).to eq([[:specific, 'a']])
    end

    it 'falls back to the generic hook with property_name and value' do
      execute('BuilderFilterGenericOnlyDispatch', "name eq 'a'")
      expect(BuilderFilterDispatchCapture.calls).to eq([[:generic, :name, 'a']])
    end

    it 'raises NoImplementationError naming the property and operation' do
      expect { execute('BuilderFilterNoHookDispatch', "name gt 'a'") }
        .to raise_error(OdataDuty::NoImplementationError, 'name gt not supported')
    end
  end
end
