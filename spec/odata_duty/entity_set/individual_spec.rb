require 'spec_helper'

class IndividualTestEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class SupportsIndividualSet < OdataDuty::EntitySet
  entity_type IndividualTestEntity

  def individual(id)
    [OpenStruct.new(id: '1')].find { |x| x.id == id }
  end
end

class DoesNotSupportIndividualSet < OdataDuty::EntitySet
  entity_type IndividualTestEntity
end

class IndividualIntegerTestEntity < OdataDuty::EntityType
  property_ref 'id', Integer
end

class IndividualIntegerSet < OdataDuty::EntitySet
  entity_type IndividualIntegerTestEntity

  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id }
  end
end

class IndividualTestSchema < OdataDuty::Schema
  entity_sets [SupportsIndividualSet, DoesNotSupportIndividualSet, IndividualIntegerSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can specific individual result' do
  subject(:schema) { IndividualTestSchema }

  describe '#execute' do
    describe 'individual' do
      it do
        json_string = schema.execute("SupportsIndividual('1')", context: Context.new)
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => '$metadata#SupportsIndividual/$entity',
            '@odata.id' => 'SupportsIndividual(\'1\')',
            'id' => '1'
          }
        )
      end

      it do
        json_string = schema.execute('IndividualInteger(1)', context: Context.new)
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => '$metadata#IndividualInteger/$entity',
            '@odata.id' => 'IndividualInteger(1)',
            'id' => 1
          }
        )
      end

      it do
        expect do
          schema.execute("DoesNotSupportIndividual('1')", context: Context.new)
        end.to raise_error(OdataDuty::NoImplementionError)
      end
    end
  end
end
