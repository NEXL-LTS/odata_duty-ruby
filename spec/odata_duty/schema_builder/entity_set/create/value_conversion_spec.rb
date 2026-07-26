require 'spec_helper'

class ValueConversionResolver < OdataDuty::SetResolver
  def create(input)
    OpenStruct.new(id: input.id, count: input.count, numbers: input.numbers)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'typed value conversion on create input' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'ValueConversion') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'count', Integer
          et.property 'numbers', [Integer]
        end

        s.add_entity_set(name: 'ValueConversions', entity_type: entity,
                         resolver: 'ValueConversionResolver')
      end
    end

    def create(options)
      Oj.load(schema.create('ValueConversions', context: Context.new,
                                                query_options: { 'id' => '1' }.merge(options)))
    end

    it 'coerces a numeric string to an integer for a scalar property' do
      expect(create('count' => '42')).to include('count' => 42)
    end

    it 'passes a nil scalar value through without coercion' do
      expect(create('count' => nil)).to include('count' => nil)
    end

    it 'decorates a bad scalar value error with the property name' do
      expect { create('count' => 'not-a-number') }
        .to raise_error(InvalidType, /count : /)
    end

    it 'returns the coerced elements of a collection scalar property' do
      expect(create('numbers' => %w[1 2])).to include('numbers' => [1, 2])
    end

    it 'names the offending value and property when the collection value is not enumerable' do
      expect { create('numbers' => 5) }
        .to raise_error(InvalidType, /numbers : 5 is not an collection/)
    end
  end
end
