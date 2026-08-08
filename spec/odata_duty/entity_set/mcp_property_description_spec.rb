require 'spec_helper'

class McpDescriptionEntity < OdataDuty::EntityType
  property_ref 'id', String, description: 'Server-assigned identifier'
  property 'user_name', String, nullable: false, description: 'Unique login handle'
end

class McpDescriptionSet < OdataDuty::EntitySet
  entity_type McpDescriptionEntity
  name 'People'
  url 'People'

  def od_after_init
    @records = [OpenStruct.new(id: '1', user_name: 'user1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end

  def create(params)
    params
  end

  def update(_id, params)
    params
  end
end

class McpDescriptionCollisionEntity < OdataDuty::EntityType
  property_ref 'odata_select', String, description: 'Looks like a reserved alias'
end

class McpDescriptionCollisionSet < OdataDuty::EntitySet
  entity_type McpDescriptionCollisionEntity
  name 'CollisionPeople'
  url 'CollisionPeople'

  def od_after_init
    @records = [OpenStruct.new(odata_select: '1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.odata_select == id }
  end
end

class McpDescriptionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [McpDescriptionSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP property description' do
  let(:mcp_server) do
    server = McpDescriptionSchema.to_mcp_server
    server.server_context = { context: Context.new }
    server
  end

  def call(payload)
    Oj.load(mcp_server.handle_json(Oj.dump(payload)))
  end

  let(:tools) do
    request_payload = { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {},
                        'id' => 'tl-1' }
    call(request_payload)['result']['tools']
  end

  def tool(name)
    tools.find { |t| t['name'] == name }
  end

  it 'carries the property description on the create tool input schema' do
    expect(tool('create_People')['inputSchema']['properties']['user_name'])
      .to include('description' => 'Unique login handle')
  end

  it 'carries the property description on the update tool input schema' do
    expect(tool('update_People')['inputSchema']['properties']['user_name'])
      .to include('description' => 'Unique login handle')
  end

  it 'carries the key property description on the get tool input schema' do
    expect(tool('get_People')['inputSchema']['properties']['id'])
      .to include('description' => 'Server-assigned identifier')
  end

  it 'still raises the reserved-key collision error for a described colliding property' do
    schema = Class.new(OdataDuty::Schema) do
      base_url 'http://localhost:3000/api'
      entity_sets [McpDescriptionCollisionSet]
    end

    expect { schema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      'McpDescriptionCollisionEntity property "odata_select" collides with the reserved ' \
      'odata_select query-option key in the get_CollisionPeople tool input schema'
    )
  end
end
