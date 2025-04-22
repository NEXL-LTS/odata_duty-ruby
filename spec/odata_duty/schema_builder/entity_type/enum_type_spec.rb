require 'spec_helper'

class EnumResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: '1', enum: 'one', maybe: nil),
      OpenStruct.new(id: '2', enum: 'two', maybe: 'one'),
      OpenStruct.new(id: '3', enum: 'one', maybe: 'two')
    ]
  end

  def od_filter_enum_eq(value)
    @records = @records.select { |r| r.enum == value }
  end

  def od_filter_maybe_eq(value)
    @records = @records.select { |r| r.maybe == value }
  end

  def collection
    @records
  end

  def count
    @records.count
  end
end

class EnumWithInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: '1', enum: 'boolean', maybe: nil)
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can use boolean primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        enum_type = s.add_enum_type(name: 'BoolValues') do |en|
          en.member 'one'
          en.member 'two'
        end

        bool_entity = s.add_entity_type(name: 'EnumValues') do |et|
          et.property_ref 'id', String
          et.property 'enum', enum_type, nullable: false
          et.property 'maybe', enum_type, nullable: true
        end

        s.add_entity_set(name: 'EnumWithInvalid', entity_type: bool_entity,
                         resolver: 'EnumWithInvalidResolver')
        s.add_entity_set(name: 'Enum', entity_type: bool_entity, resolver: 'EnumResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(schema.metadata_xml)
      end
      let(:entity_types) { entity_types_from_doc(parsed_xml) }
      let(:keys) { entity_type.fetch(:keys) }
      let(:properties) { entity_type.fetch(:properties) }

      it { expect(entity_types.keys).to contain_exactly('EnumValues') }

      describe 'EnumValues' do
        let(:entity_type) { entity_types['EnumValues'] }

        it { expect(keys).to eq(['id']) }
        it do
          expect(properties).to include(name: 'enum', nullable: 'false',
                                        type: 'SampleSpace.BoolValues')
        end
        it do
          expect(properties).to include(name: 'maybe', nullable: 'true',
                                        type: 'SampleSpace.BoolValues')
        end
      end
    end

    describe '#collection' do
      describe 'EnumSet' do
        it do
          json_string = schema.execute('Enum', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => 'https://localhost/$metadata#Enum',
              'value' => [
                { '@odata.id' => 'https://localhost/Enum(\'1\')', 'id' => '1', 'enum' => 'one',
                  'maybe' => nil },
                { '@odata.id' => 'https://localhost/Enum(\'2\')', 'id' => '2', 'enum' => 'two',
                  'maybe' => 'one' },
                { '@odata.id' => 'https://localhost/Enum(\'3\')', 'id' => '3', 'enum' => 'one', 'maybe' => 'two' }
              ]
            }
          )
        end

        it do
          json_string = schema.execute('Enum', context: Context.new,
                                               query_options: { '$filter' => 'enum eq one' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => 'https://localhost/$metadata#Enum',
              'value' => [
                { '@odata.id' => 'https://localhost/Enum(\'1\')', 'id' => '1', 'enum' => 'one',
                  'maybe' => nil },
                { '@odata.id' => 'https://localhost/Enum(\'3\')', 'id' => '3', 'enum' => 'one', 'maybe' => 'two' }
              ]
            }
          )
        end

        it do
          json_string = schema.execute('Enum', context: Context.new,
                                               query_options: { '$filter' => 'maybe eq two' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => 'https://localhost/$metadata#Enum',
              'value' => [
                { '@odata.id' => 'https://localhost/Enum(\'3\')', 'id' => '3', 'enum' => 'one', 'maybe' => 'two' }
              ]
            }
          )
        end

        it do
          result = schema.execute('Enum/$count',
                                  context: Context.new,
                                  query_options: { '$filter' => 'enum eq one' })
          expect(result).to eq(2)
        end

        it do
          expect do
            schema.execute('Enum', context: Context.new,
                                   query_options: { '$filter' => 'enum eq three' })
          end.to raise_error(OdataDuty::InvalidFilterValue)
        end
      end

      describe 'EnumWithInvalid' do
        it do
          expect do
            schema.execute('EnumWithInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
