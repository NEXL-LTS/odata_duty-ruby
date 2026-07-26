require 'spec_helper'

class PropValueConvEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'count', Integer
  property 'numbers', [Integer]
end

class PropValueConvSet < OdataDuty::EntitySet
  entity_type PropValueConvEntity

  def create(params)
    OpenStruct.new(id: params.id, count: params.count, numbers: params.numbers)
  end
end

class PropValueConvSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [PropValueConvSet]
end

RSpec.describe OdataDuty::EntitySet, 'typed property value conversion on create input' do
  subject(:schema) { PropValueConvSchema }

  def create(options)
    Oj.load(schema.create('PropValueConv', context: Context.new,
                                           query_options: { 'id' => '1' }.merge(options)))
  end

  describe 'a scalar property coerces its input value to the OData type' do
    it 'coerces a numeric string to an integer' do
      expect(create('count' => '42')).to include('count' => 42)
    end
  end

  describe 'a nil input value passes straight through without coercion' do
    it 'keeps nil for a scalar property' do
      expect(create('count' => nil)).to include('count' => nil)
    end
  end

  describe 'a bad scalar value raises with the offending property name in the message' do
    it 'decorates the InvalidValue message with the property name' do
      expect do
        create('count' => 'not-a-number')
      end.to raise_error(OdataDuty::InvalidType, /count : /)
    end
  end

  describe 'a collection scalar property coerces each element to the OData type' do
    it 'returns the coerced elements, not the original inputs' do
      expect(create('numbers' => %w[1 2])).to include('numbers' => [1, 2])
    end
  end

  describe 'a non-enumerable value for a collection property raises InvalidValue' do
    it 'names the offending value and property in the message' do
      expect do
        create('numbers' => 5)
      end.to raise_error(OdataDuty::InvalidType, /numbers : 5 is not an collection/)
    end
  end
end
