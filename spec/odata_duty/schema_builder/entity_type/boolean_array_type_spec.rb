require 'spec_helper'

class BoolArrayResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: '1', booleans: [true]),
      OpenStruct.new(id: '2', booleans: [false]),
      OpenStruct.new(id: '3', booleans: [true])
    ]
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class BoolArrayWithInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: '1', booleans: ['boolean'])
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use array boolean primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        bool_entity = s.add_entity_type(name: 'BoolValues') do |et|
          et.property_ref 'id', String
          et.property 'booleans', [TrueClass], nullable: false
        end

        s.add_entity_set(name: 'BoolWithInvalid', entity_type: bool_entity,
                         resolver: 'BoolArrayWithInvalidResolver')
        s.add_entity_set(name: 'Bool', entity_type: bool_entity,
                         resolver: 'BoolArrayResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(EdmxSchema.metadata_xml(schema))
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('BoolValues') }

      describe 'BoolValues' do
        let(:entity_type) { entity_types['BoolValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'booleans',
                                        nullable: 'false',
                                        type: 'Collection(Edm.Boolean)')
        end
      end
    end

    describe '#collection' do
      describe 'BoolSet' do
        it do
          json_string = schema.execute('Bool', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#Bool',
              'value' => [
                { '@odata.id' => 'Bool(\'1\')', 'id' => '1', 'booleans' => [true] },
                { '@odata.id' => 'Bool(\'2\')', 'id' => '2', 'booleans' => [false] },
                { '@odata.id' => 'Bool(\'3\')', 'id' => '3', 'booleans' => [true] }
              ]
            }
          )
        end

        it 'raises an error for invalid filter on collection property' do
          expect do
            schema.execute('Bool', context: Context.new,
                                   query_options: { '$filter' => 'booleans eq true' })
          end.to raise_error(OdataDuty::InvalidQueryOptionError)
        end

        it 'raises a not supported error for unsupported filter syntax' do
          expect do
            schema.execute('Bool', context: Context.new,
                                   query_options: { '$filter' => 'booleans/any(t: t eq true)' })
          end.to raise_error(OdataDuty::NotYetSupportedError)
        end
      end

      describe 'BoolWithInvalid' do
        it 'raises an error for invalid value in the collection' do
          expect do
            schema.execute('BoolWithInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
