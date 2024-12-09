require 'spec_helper'

class MethodOverrideEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'over', String
  property 'second_id', String, method: :id
  property 'second_over', String, method: :over

  def over
    'overridden'
  end
end

class MethodOverrideSet < OdataDuty::EntitySet
  entity_type MethodOverrideEntity

  def collection
    [OpenStruct.new(id: '1')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class MethodOverrideTestsSchema < OdataDuty::Schema
  entity_sets [MethodOverrideSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can Override the default name and/or url' do
  subject(:schema) { MethodOverrideTestsSchema }

  describe '#execute' do
    describe 'collection' do
      it do
        response = Oj.load(schema.execute('MethodOverride', context: Context.new))
        expect(response).to eq(
          'value' => [{
            '@odata.id' => 'MethodOverride(\'1\')',
            'id' => '1',
            'second_id' => '1',
            'over' => 'overridden',
            'second_over' => 'overridden'
          }],
          '@odata.context' => '$metadata#MethodOverride'
        )
      end
    end
  end
end
