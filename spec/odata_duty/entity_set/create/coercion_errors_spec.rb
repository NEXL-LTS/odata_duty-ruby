require 'spec_helper'

class CoercionGenderEnum < OdataDuty::EnumType
  member 'Male'
  member 'Female'
end

class CoercionErrorsEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'number', Integer
  property 'date', Date
  property 'datetime', DateTime
  property 'gender', CoercionGenderEnum
  property 'string_list', [String]
end

class CoercionErrorsSet < OdataDuty::EntitySet
  entity_type CoercionErrorsEntity

  def create(params)
    raise 'expected number to be a known property' unless params.respond_to?(:number)
    raise 'did not expect unknown property' if params.respond_to?(:not_a_property)

    %i[id number date datetime gender string_list].each { |key| params.public_send(key) }
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

  it 'raises for a non-integer number' do
    expect { create('id' => '1', 'number' => 'not-a-number') }
      .to raise_error(OdataDuty::InvalidType, /number/)
  end

  it 'raises for an invalid date' do
    expect { create('id' => '1', 'date' => 12_345) }
      .to raise_error(OdataDuty::InvalidType, /date/)
  end

  it 'raises for an invalid datetime' do
    expect { create('id' => '1', 'datetime' => 12_345) }
      .to raise_error(OdataDuty::InvalidType, /datetime/)
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
