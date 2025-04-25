require 'spec_helper'

class ForceDateTime
  def initialize(value)
    @value = value
  end

  def to_datetime
    DateTime.parse(@value.to_s)
  end
end

class DateTimeArrayResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, datetimes: [DateTime.new(2023, 1, 1, 12, 0, 0),
                                        DateTime.new(2023, 1, 2, 12, 0, 0)]),
      OpenStruct.new(id: 2, datetimes: []),
      OpenStruct.new(id: 3, datetimes: [ForceDateTime.new('2023-01-03T12:00:00')]),
      OpenStruct.new(id: 4, datetimes: nil),
      OpenStruct.new(id: 5, datetimes: [nil])
    ]
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class DateTimeArrayInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: 1, datetimes: [:invalid_datetime])
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use array datetime primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        datetime_entity = s.add_entity_type(name: 'DateTimeValues') do |et|
          et.property_ref 'id', Integer
          et.property 'datetimes', [DateTime], nullable: true
        end

        s.add_entity_set(name: 'DateTimeInvalid', entity_type: datetime_entity,
                         resolver: 'DateTimeArrayInvalidResolver')
        s.add_entity_set(name: 'DateTime', entity_type: datetime_entity,
                         resolver: 'DateTimeArrayResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(schema.metadata_xml)
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('DateTimeValues') }

      describe 'DateTimeValues' do
        let(:entity_type) { entity_types['DateTimeValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'datetimes',
                                        type: 'Collection(Edm.DateTimeOffset)',
                                        nullable: 'true')
        end
      end
    end

    describe '#collection' do
      describe 'DateTimeArrayResolver' do
        it do
          json_string = schema.execute('DateTime', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            'value' => [
              { '@odata.id' => 'https://localhost/DateTime(1)', 'id' => 1,
                'datetimes' => ['2023-01-01T12:00:00+00:00', '2023-01-02T12:00:00+00:00'] },
              { '@odata.id' => 'https://localhost/DateTime(2)', 'id' => 2, 'datetimes' => [] },
              { '@odata.id' => 'https://localhost/DateTime(3)', 'id' => 3,
                'datetimes' => ['2023-01-03T12:00:00+00:00'] },
              { '@odata.id' => 'https://localhost/DateTime(4)', 'id' => 4, 'datetimes' => nil },
              { '@odata.id' => 'https://localhost/DateTime(5)', 'id' => 5, 'datetimes' => [nil] }
            ],
            '@odata.context' => 'https://localhost/$metadata#DateTime'
          )
        end
      end

      describe 'DateTimeArrayInvalidResolver' do
        it do
          expect do
            schema.execute('DateTimeInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
