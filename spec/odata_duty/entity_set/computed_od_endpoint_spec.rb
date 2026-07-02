require 'spec_helper'

class OdEndpointComputedEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'endpoint_name', String

  def endpoint_name
    od_endpoint.name
  end
end

class OdEndpointComputedSet < OdataDuty::EntitySet
  entity_type OdEndpointComputedEntity

  def collection
    [OpenStruct.new(id: '1')]
  end
end

class OdEndpointComputedSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [OdEndpointComputedSet]
end

RSpec.describe OdataDuty::EntityType, 'od_endpoint helper in a computed property' do
  it 'exposes the current endpoint to a computed property method' do
    json = OdEndpointComputedSchema.execute('OdEndpointComputed', context: Context.new)
    expect(Oj.load(json)['value'].first['endpoint_name']).to eq('OdEndpointComputed')
  end
end
