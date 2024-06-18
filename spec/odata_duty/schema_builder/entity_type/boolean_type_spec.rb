require 'spec_helper'

class BoolResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: '1', boolean: true, maybe: nil),
      OpenStruct.new(id: '2', boolean: false, maybe: true),
      OpenStruct.new(id: '3', boolean: true, maybe: false)
    ]
  end

  def od_filter_boolean_eq(value)
    @records = @records.select { |r| r.boolean == value }
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

class BoolWithInvalidResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: '1', boolean: 'boolean', maybe: nil)
    ]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can use boolean primitive type' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', base_url: 'http://localhost') do |s|
        bool_entity = s.add_entity_type(name: 'BoolValues') do |et|
          et.property_ref 'id', String
          et.property 'boolean', TrueClass, nullable: false
          et.property 'maybe', TrueClass, nullable: true
        end

        s.add_entity_set(name: 'BoolWithInvalid', entity_type: bool_entity,
                         resolver: 'BoolWithInvalidResolver')
        s.add_entity_set(name: 'Bool', entity_type: bool_entity, resolver: 'BoolResolver')
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
        it {
          expect(properties).to include(name: 'boolean', nullable: 'false', type: 'Edm.Boolean')
        }
        it { expect(properties).to include(name: 'maybe', nullable: 'true', type: 'Edm.Boolean') }
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
                { '@odata.id' => 'Bool(\'1\')', 'id' => '1', 'boolean' => true, 'maybe' => nil },
                { '@odata.id' => 'Bool(\'2\')', 'id' => '2', 'boolean' => false, 'maybe' => true },
                { '@odata.id' => 'Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
              ]
            }
          )
        end

        it do
          json_string = schema.execute('Bool', context: Context.new,
                                               query_options: { '$filter' => 'boolean eq true' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#Bool',
              'value' => [
                { '@odata.id' => 'Bool(\'1\')', 'id' => '1', 'boolean' => true, 'maybe' => nil },
                { '@odata.id' => 'Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
              ]
            }
          )
        end

        it do
          json_string = schema.execute('Bool', context: Context.new,
                                               query_options: { '$filter' => 'maybe eq false' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#Bool',
              'value' => [
                { '@odata.id' => 'Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
              ]
            }
          )
        end

        it do
          result = schema.execute('Bool/$count',
                                  context: Context.new,
                                  query_options: { '$filter' => 'boolean eq true' })
          expect(result).to eq(2)
        end

        it do
          expect do
            schema.execute('Bool', context: Context.new,
                                   query_options: { '$filter' => 'boolean eq blueblah' })
          end.to raise_error(OdataDuty::InvalidFilterValue)
        end
      end

      describe 'BoolWithInvalid' do
        it do
          expect do
            schema.execute('BoolWithInvalid', context: Context.new)
          end.to raise_error(OdataDuty::InvalidValue)
        end
      end
    end
  end
end
