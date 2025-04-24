require 'spec_helper'

class ForceDate
  def initialize(value)
    @value = value
  end

  def to_date
    Date.parse(@value.to_s)
  end
end

class DateArrayResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, dates: [Date.new(2023, 1, 1), Date.new(2023, 1, 2)]),
      OpenStruct.new(id: 2, dates: []),
      OpenStruct.new(id: 3, dates: [ForceDate.new('2023-01-03')]),
      OpenStruct.new(id: 4, dates: nil),
      OpenStruct.new(id: 5, dates: [nil])
    ]
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class DateArrayInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: 1, dates: [:invalid_date])
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use array date primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        date_entity = s.add_entity_type(name: 'DateValues') do |et|
          et.property_ref 'id', Integer
          et.property 'dates', [Date], nullable: true
        end

        s.add_entity_set(name: 'DateInvalid', entity_type: date_entity,
                         resolver: 'DateArrayInvalidResolver')
        s.add_entity_set(name: 'Date', entity_type: date_entity,
                         resolver: 'DateArrayResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(schema.metadata_xml)
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('DateValues') }

      describe 'DateValues' do
        let(:entity_type) { entity_types['DateValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'dates',
                                        type: 'Collection(Edm.Date)',
                                        nullable: 'true')
        end
      end
    end

    describe '#collection' do
      describe 'DateArrayResolver' do
        it do
          json_string = schema.execute('Date', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            'value' => [
              { '@odata.id' => 'https://localhost/Date(1)', 'id' => 1,
                'dates' => %w[2023-01-01 2023-01-02] },
              { '@odata.id' => 'https://localhost/Date(2)', 'id' => 2, 'dates' => [] },
              { '@odata.id' => 'https://localhost/Date(3)', 'id' => 3, 'dates' => ['2023-01-03'] },
              { '@odata.id' => 'https://localhost/Date(4)', 'id' => 4, 'dates' => nil },
              { '@odata.id' => 'https://localhost/Date(5)', 'id' => 5, 'dates' => [nil] }
            ],
            '@odata.context' => 'https://localhost/$metadata#Date'
          )
        end
      end

      describe 'DateArrayInvalidResolver' do
        it do
          expect do
            schema.execute('DateInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
