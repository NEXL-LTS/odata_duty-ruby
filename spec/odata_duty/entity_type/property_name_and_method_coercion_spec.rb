require 'spec_helper'

module OdataDuty
  RSpec.describe EntityType, 'property value from an entity instance method' do
    let(:schema) do
      entity = Class.new(EntityType) do
        property_ref 'id', String
        property 'greeting', String

        def greeting
          "hello-#{object.id}"
        end
      end
      set = Class.new(EntitySet) do
        entity_type entity
        url 'InstanceMethod'

        def collection
          [OpenStruct.new(id: '1')]
        end
      end
      Class.new(Schema) do
        base_url 'http://localhost:3000/api'
        entity_sets [set]
      end
    end

    it 'reads the property from the entity instance method, not the data object' do
      json = schema.execute('InstanceMethod', context: Context.new)
      greeting = Oj.load(json)['value'].first['greeting']
      expect(greeting).to eq('hello-1')
    end
  end
end
