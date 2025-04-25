require 'spec_helper'

class ForceStr
  def initialize(value)
    @value = value
  end

  def to_str
    @value.to_s
  end
end

class StringArrayResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, strings: %w[t r]),
      OpenStruct.new(id: 2, strings: []),
      OpenStruct.new(id: 3, strings: [ForceStr.new(:sym)]),
      OpenStruct.new(id: 4, strings: nil),
      OpenStruct.new(id: 5, strings: [nil])
    ]
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class StringArraySymbolInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: 1, strings: [:sym])
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use array string primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        bool_entity = s.add_entity_type(name: 'StringValues') do |et|
          et.property_ref 'id', Integer
          et.property 'strings', [String], nullable: true
        end

        s.add_entity_set(name: 'StrInvalid', entity_type: bool_entity,
                         resolver: 'StringArraySymbolInvalidResolver')
        s.add_entity_set(name: 'Str', entity_type: bool_entity,
                         resolver: 'StringArrayResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(schema.metadata_xml)
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('StringValues') }

      describe 'StringValues' do
        let(:entity_type) { entity_types['StringValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'strings',
                                        type: 'Collection(Edm.String)',
                                        nullable: 'true')
        end
      end
    end

    describe '#collection' do
      describe 'StringArrayResolver' do
        it do
          json_string = schema.execute('Str', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            'value' => [
              { '@odata.id' => 'https://localhost/Str(1)', 'id' => 1, 'strings' => %w[t r] },
              { '@odata.id' => 'https://localhost/Str(2)', 'id' => 2, 'strings' => [] },
              { '@odata.id' => 'https://localhost/Str(3)', 'id' => 3, 'strings' => ['sym'] },
              { '@odata.id' => 'https://localhost/Str(4)', 'id' => 4, 'strings' => nil },
              { '@odata.id' => 'https://localhost/Str(5)', 'id' => 5, 'strings' => [nil] }
            ],
            '@odata.context' => 'https://localhost/$metadata#Str'
          )
        end
      end

      describe 'StringArraySymbolInvalidResolver' do
        it do
          expect do
            schema.execute('StrInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
