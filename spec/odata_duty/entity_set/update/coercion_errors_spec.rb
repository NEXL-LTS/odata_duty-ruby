require 'spec_helper'

class UpdateCoercionEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'string', String
  property 'number', Integer
  property 'date', Date
  property 'datetime', DateTime
  property 'bool', TrueClass
end

class UpdateCoercionSet < OdataDuty::EntitySet
  entity_type UpdateCoercionEntity

  def update(id, params)
    %i[string number date datetime bool].each { |key| params.public_send(key) }
    OpenStruct.new(id: id)
  end
end

class UpdateCoercionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UpdateCoercionSet]
end

RSpec.describe OdataDuty::EntitySet, 'update input coercion errors' do
  subject(:schema) { UpdateCoercionSchema }

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
