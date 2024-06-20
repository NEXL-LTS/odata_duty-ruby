require 'spec_helper'

AlternativeMethodStruct = Struct.new(:id, :alternative_string, :alternative_complex)

class AlternativeMethodResolver < OdataDuty::SetResolver
  def collection
    [
      AlternativeMethodStruct.new('1', 'alternative_string',
                                  OpenStruct.new(string: 'complex_string'))
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can suggest an alternative method' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        a_complex_type = s.add_complex_type(name: 'SimpleComplex') do |et|
          et.property 'string', String
        end

        alternative_entity = s.add_entity_type(name: 'AlternativeMethod') do |et|
          et.property_ref 'id', String
          et.property 'string', String, method: :alternative_string
          et.property 'combined', String, method: ->(e) { "#{e.id}-#{e.alternative_string}" }
          et.property 'complex', a_complex_type, method: :alternative_complex
        end

        s.add_entity_set(name: 'AlternativeMethods', entity_type: alternative_entity,
                         resolver: 'AlternativeMethodResolver')
      end
    end

    describe '#collection' do
      it do
        json_string = schema.execute('AlternativeMethods', context: Context.new)
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => '$metadata#AlternativeMethods',
            'value' => [
              { '@odata.id' => 'AlternativeMethods(\'1\')',
                'id' => '1',
                'string' => 'alternative_string',
                'combined' => '1-alternative_string',
                'complex' => { 'string' => 'complex_string' } }
            ]
          }
        )
      end
    end
  end
end
