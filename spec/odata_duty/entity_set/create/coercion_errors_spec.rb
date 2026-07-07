require 'spec_helper'

class CoercionGenderEnum < OdataDuty::EnumType
  member 'Male'
  member 'Female'
end

class CoercionErrorsEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'string', String
  property 'number', Integer
  property 'date', Date
  property 'datetime', DateTime
  property 'bool', TrueClass
  property 'gender', CoercionGenderEnum
  property 'string_list', [String]
end

class CoercionErrorsSet < OdataDuty::EntitySet
  entity_type CoercionErrorsEntity

  def create(params)
    raise 'expected number to be a known property' unless params.respond_to?(:number)
    raise 'did not expect unknown property' if params.respond_to?(:not_a_property)

    %i[id string number date datetime bool gender string_list].each do |key|
      params.public_send(key)
    end
    params
  end
end

class CoercionErrorsSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CoercionErrorsSet]
end

RSpec.describe OdataDuty::EntitySet, 'create input coercion errors' do
  subject(:schema) { CoercionErrorsSchema }

  def create(body)
    schema.create('CoercionErrors', context: Context.new, query_options: body)
  end

  it 'raises for a non-integer number, appending the underlying reason' do
    expect { create('id' => '1', 'number' => 'not-a-number') }
      .to raise_error(OdataDuty::InvalidType,
                      /'number' is of wrong type:.*invalid value for Integer/)
  end

  it 'raises for a non-string, appending the underlying reason' do
    expect { create('id' => '1', 'string' => 1) }
      .to raise_error(OdataDuty::InvalidType, /'string' is of wrong type:.*to_str/)
  end

  it 'raises for an invalid date, appending the underlying reason' do
    expect { create('id' => '1', 'date' => '2021-01-32') }
      .to raise_error(OdataDuty::InvalidType, /'date' is of wrong type:.*invalid date/)
  end

  it 'raises for an invalid datetime, appending the underlying reason' do
    expect { create('id' => '1', 'datetime' => '2021-01-01T99:99:99') }
      .to raise_error(OdataDuty::InvalidType, /'datetime' is of wrong type:.+/)
  end

  it 'raises for a non-boolean, appending the underlying reason' do
    expect { create('id' => '1', 'bool' => 'not-a-bool') }
      .to raise_error(OdataDuty::InvalidType, /'bool' is of wrong type:.*not-a-bool not boolean/)
  end

  it 'raises for an invalid enum member' do
    expect { create('id' => '1', 'gender' => 'Other') }
      .to raise_error(OdataDuty::InvalidType, /gender/)
  end

  it 'accepts a valid enum member' do
    json = create('id' => '1', 'gender' => 'Male')
    expect(Oj.load(json)['gender']).to eq('Male')
  end

  it 'raises when a collection is not enumerable' do
    expect { create('id' => '1', 'string_list' => 'not-a-list') }
      .to raise_error(OdataDuty::InvalidType, /string_list/)
  end
end
