require 'spec_helper'

class BoolEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'boolean', TrueClass, nullable: false
  property 'maybe', TrueClass, nullable: true
end

class BoolSet < OdataDuty::EntitySet
  entity_type BoolEntity

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

class BoolWithInvalidSet < OdataDuty::EntitySet
  entity_type BoolEntity

  def collection
    [
      OpenStruct.new(id: '1', boolean: 'boolean', maybe: nil)
    ]
  end
end

class BooleanTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [BoolSet, BoolWithInvalidSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can use boolean primitive type' do
  subject(:schema) { BooleanTestSchema }

  describe '#metadata_xml' do
    let(:parsed_xml) do
      parse_xml_from_string(schema.metadata_xml)
    end
    let(:entity_types) { entity_types_from_doc(parsed_xml) }
    let(:keys) { entity_type.fetch(:keys) }
    let(:properties) { entity_type.fetch(:properties) }

    it { expect(entity_types.keys).to contain_exactly('Bool') }

    describe 'Bool' do
      let(:entity_type) { entity_types['Bool'] }

      it { expect(keys).to eq(['id']) }
      it { expect(properties).to include(name: 'boolean', nullable: 'false', type: 'Edm.Boolean') }
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
            '@odata.context' => 'http://localhost:3000/api/$metadata#Bool',
            'value' => [
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'1\')', 'id' => '1',
                'boolean' => true, 'maybe' => nil },
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'2\')', 'id' => '2',
                'boolean' => false, 'maybe' => true },
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
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
            '@odata.context' => 'http://localhost:3000/api/$metadata#Bool',
            'value' => [
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'1\')', 'id' => '1',
                'boolean' => true, 'maybe' => nil },
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
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
            '@odata.context' => 'http://localhost:3000/api/$metadata#Bool',
            'value' => [
              { '@odata.id' => 'http://localhost:3000/api/Bool(\'3\')', 'id' => '3', 'boolean' => true, 'maybe' => false }
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
