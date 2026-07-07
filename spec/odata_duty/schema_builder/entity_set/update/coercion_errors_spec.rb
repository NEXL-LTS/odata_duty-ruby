require 'spec_helper'

class UpdateCoercionResolver < OdataDuty::SetResolver
  def update(id, params)
    %i[string number date datetime bool].each { |key| params.public_send(key) }
    OpenStruct.new(id: id)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'update input coercion errors' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'UpdateCoercionEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'string', String
          et.property 'number', Integer
          et.property 'date', Date
          et.property 'datetime', DateTime
          et.property 'bool', TrueClass
        end

        s.add_entity_set(name: 'UpdateCoercion', entity_type: entity,
                         resolver: 'UpdateCoercionResolver')
      end
    end

    def update(body)
      schema.update("UpdateCoercion('1')", context: Context.new, query_options: body)
    end

    it 'raises for a non-integer number, appending the underlying reason' do
      expect { update('number' => 'not-a-number') }
        .to raise_error(OdataDuty::InvalidType,
                        /'number' is of wrong type:.*invalid value for Integer/)
    end

    it 'raises for a non-string, appending the underlying reason' do
      expect { update('string' => 1) }
        .to raise_error(OdataDuty::InvalidType, /'string' is of wrong type:.*to_str/)
    end

    it 'raises for an invalid date, appending the underlying reason' do
      expect { update('date' => '2021-01-32') }
        .to raise_error(OdataDuty::InvalidType, /'date' is of wrong type:.*invalid date/)
    end

    it 'raises for an invalid datetime, appending the underlying reason' do
      expect { update('datetime' => '2021-01-01T99:99:99') }
        .to raise_error(OdataDuty::InvalidType, /'datetime' is of wrong type:.+/)
    end

    it 'raises for a non-boolean, appending the underlying reason' do
      expect { update('bool' => 'not-a-bool') }
        .to raise_error(OdataDuty::InvalidType, /'bool' is of wrong type:.*not-a-bool not boolean/)
    end
  end
end
