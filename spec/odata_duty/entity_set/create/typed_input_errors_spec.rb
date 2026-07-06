require 'spec_helper'

class TypedInputErrorsEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'first_name', String
end

class ReadsUndefinedPropertySet < OdataDuty::EntitySet
  entity_type TypedInputErrorsEntity

  def create(input)
    input.nickname
  end
end

class AccessorWithArgumentSet < OdataDuty::EntitySet
  entity_type TypedInputErrorsEntity

  def create(input)
    input.first_name('unexpected')
  end
end

class TypedInputErrorsSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ReadsUndefinedPropertySet, AccessorWithArgumentSet]
end

RSpec.describe OdataDuty::EntitySet, 'typed input error contracts' do
  subject(:schema) { TypedInputErrorsSchema }

  def create(name)
    schema.create(name, context: Context.new, query_options: { 'id' => '1' })
  end

  it 'raises NoSuchPropertyError with an exact message when reading an undefined property' do
    expect { create('ReadsUndefinedProperty') }
      .to raise_error(OdataDuty::NoSuchPropertyError, "No such property 'nickname'")
  end

  it 'raises NoSuchPropertyError when a property accessor is called with an argument' do
    expect { create('AccessorWithArgument') }
      .to raise_error(OdataDuty::NoSuchPropertyError)
  end
end
