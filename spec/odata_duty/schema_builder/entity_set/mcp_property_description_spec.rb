require 'spec_helper'

class McpDescriptionCollisionResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1', odata_select: 'x')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end
end

class McpDescriptionPeopleResolver < OdataDuty::SetResolver
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

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP property description' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'McpDescriptionPerson') do |et|
          et.property_ref 'id', String, description: 'Server-assigned identifier'
          et.property 'user_name', String, nullable: false,
                                           description: 'Unique login handle'
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'McpDescriptionPeopleResolver')
      end
    end

    let(:mcp_server) do
      server = schema.to_mcp_server
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
      colliding_schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                             base_path: '') do |s|
        entity = s.add_entity_type(name: 'CollisionEntity') do |et|
          et.property_ref 'odata_select', String, description: 'Looks like a reserved alias'
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'McpDescriptionCollisionResolver')
      end

      expect { colliding_schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        'CollisionEntity property "odata_select" collides with the reserved odata_select ' \
        'query-option key in the get_People tool input schema'
      )
    end
  end
end
