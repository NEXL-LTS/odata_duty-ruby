require 'spec_helper'

class BoolCoercionResolver < OdataDuty::SetResolver
  def create(params)
    params
  end
end

class BuilderTruthyValue
  def to_boolean # rubocop:disable Naming/PredicateMethod
    true
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Edm.Boolean create coercion' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'BoolCoercion') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'flag', TrueClass
        end

        s.add_entity_set(name: 'BoolCoercion', entity_type: entity,
                         resolver: 'BoolCoercionResolver')
      end
    end

    def response(flag)
      json_string = schema.create('BoolCoercion', context: Context.new,
                                                  query_options: { 'id' => '1', 'flag' => flag })
      Oj.load(json_string)
    end

    it 'coerces a body value via its own to_boolean' do
      expect(response(BuilderTruthyValue.new)).to include('flag' => true)
    end
  end
end
