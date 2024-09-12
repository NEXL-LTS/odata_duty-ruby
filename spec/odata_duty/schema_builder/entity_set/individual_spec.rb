require 'spec_helper'

class SupportsIndividualResolver < OdataDuty::SetResolver
  def individual(id)
    [OpenStruct.new(id: '1')].find { |x| x.id == id.to_str }
  end
end

class DoesNotSupportIndividualResolver < OdataDuty::SetResolver
end

class IndividualIntegerResolver < OdataDuty::SetResolver
  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id.to_int }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can specific individual result' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        string_entity = s.add_entity_type(name: 'IndividualTest') do |et|
          et.property_ref 'id', String
        end
        integer_entity = s.add_entity_type(name: 'IndividualIntegerTest') do |et|
          et.property_ref 'id', Integer
        end

        s.add_entity_set(entity_type: string_entity, resolver: 'SupportsIndividualResolver')
        s.add_entity_set(entity_type: string_entity, resolver: 'DoesNotSupportIndividualResolver')
        s.add_entity_set(entity_type: integer_entity, resolver: 'IndividualIntegerResolver')
      end
    end

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
          end.to raise_error(OdataDuty::NoImplementationError)
        end
      end
    end
  end
end
