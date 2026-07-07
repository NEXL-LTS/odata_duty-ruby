require 'spec_helper'

class BoolCoercionEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'flag', TrueClass
end

class BoolCoercionSet < OdataDuty::EntitySet
  entity_type BoolCoercionEntity

  def create(params)
    params
  end
end

class BoolCoercionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [BoolCoercionSet]
end

class TruthyValue
  def to_boolean # rubocop:disable Naming/PredicateMethod
    true
  end
end

RSpec.describe OdataDuty::EntitySet, 'Edm.Boolean create coercion' do
  subject(:schema) { BoolCoercionSchema }

  def response(flag)
    json_string = schema.create('BoolCoercion', context: Context.new,
                                                query_options: { 'id' => '1', 'flag' => flag })
    Oj.load(json_string)
  end

  it 'coerces a body value via its own to_boolean' do
    expect(response(TruthyValue.new)).to include('flag' => true)
  end
end
