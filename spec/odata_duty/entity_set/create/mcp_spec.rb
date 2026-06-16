require 'spec_helper'

class CreateMcpStruct
  attr_reader :id, :name

  def initialize(id:, name:)
    @id = id
    @name = name
  end
end

class CreateMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class CreateMcpWidgetSet < OdataDuty::EntitySet
  entity_type CreateMcpWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def create(params)
    CreateMcpStruct.new(id: 'w1', name: params.name)
  end
end

class CreateMcpPersonSet < OdataDuty::EntitySet
  entity_type CreateMcpWidgetEntity
  name 'People'
  url 'People'
end

class CreateMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CreateMcpWidgetSet, CreateMcpPersonSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP create tool' do
  subject(:mcp_server) { CreateMcpSchema }

  describe 'tools/list' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 'tl-1' }
    end

    let(:tools) do
      Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))['result']['tools']
    end

    it 'includes a create tool for entity sets that support create' do
      expect(tools).to include(
        'name' => 'create_Widgets',
        'description' => 'Create a new Widgets record',
        'inputSchema' => {
          'type' => 'object',
          'properties' => {
            'id' => { 'type' => 'string' },
            'name' => { 'type' => 'string', 'x-nullable' => true }
          },
          'required' => ['id']
        }
      )
    end

    it 'does not include a create tool for read-only entity sets' do
      expect(tools.map { |t| t['name'] }).not_to include('create_People')
    end
  end

  describe 'tools/call for create' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'create_Widgets', 'arguments' => { 'name' => 'Gadget' } },
        'id' => 'tc-1' }
    end

    it 'creates the record and returns it as structured JSON' do
      actual = Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))

      expect(actual['result']).to include('id' => 'w1', 'name' => 'Gadget')
    end

    it 'raises Unknown tool for a create tool on a read-only set' do
      request_payload['params']['name'] = 'create_People'

      expect do
        mcp_server.handle_jsonrpc(request_payload, context: Context.new)
      end.to raise_error(/Unknown tool/)
    end
  end
end
