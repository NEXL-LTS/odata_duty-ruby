require 'spec_helper'

class ForceInt
  def initialize(value)
    @value = value
  end

  def to_int
    @value.to_i
  end
end

class IntegerArrayResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, integers: [1, 2]),
      OpenStruct.new(id: 2, integers: []),
      OpenStruct.new(id: 3, integers: [ForceInt.new('101')]),
      OpenStruct.new(id: 4, integers: nil),
      OpenStruct.new(id: 5, integers: [nil])
    ]
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class IntegerArraySymbolInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: 1, integers: [:sym])
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use array integer primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        bool_entity = s.add_entity_type(name: 'IntegerValues') do |et|
          et.property_ref 'id', Integer
          et.property 'integers', [Integer], nullable: true
        end

        s.add_entity_set(name: 'IntInvalid', entity_type: bool_entity,
                         resolver: 'IntegerArraySymbolInvalidResolver')
        s.add_entity_set(name: 'Int', entity_type: bool_entity,
                         resolver: 'IntegerArrayResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(schema.metadata_xml)
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('IntegerValues') }

      describe 'IntegerValues' do
        let(:entity_type) { entity_types['IntegerValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'integers',
                                        type: 'Collection(Edm.Int64)',
                                        nullable: 'true')
        end
      end
    end

    describe '#collection' do
      describe 'IntegerArrayResolver' do
        it do
          json_string = schema.execute('Int', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            'value' => [
              { '@odata.id' => 'https://localhost/Int(1)', 'id' => 1, 'integers' => [1, 2] },
              { '@odata.id' => 'https://localhost/Int(2)', 'id' => 2, 'integers' => [] },
              { '@odata.id' => 'https://localhost/Int(3)', 'id' => 3, 'integers' => [101] },
              { '@odata.id' => 'https://localhost/Int(4)', 'id' => 4, 'integers' => nil },
              { '@odata.id' => 'https://localhost/Int(5)', 'id' => 5, 'integers' => [nil] }
            ],
            '@odata.context' => 'https://localhost/$metadata#Int'
          )
        end
      end

      describe 'IntegerArraySymbolInvalidResolver' do
        it do
          expect do
            schema.execute('IntInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
