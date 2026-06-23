require 'spec_helper'

class CreateMcpStruct
  attr_reader :id, :name, :sku, :created_at

  def initialize(id:, name:, sku:)
    @id = id
    @name = name
    @sku = sku
    @created_at = '2026-06-23'
  end
end

class CreateMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'sku', String, nullable: false
  property 'created_at', String, computed: true
end

class CreateMcpWidgetSet < OdataDuty::EntitySet
  entity_type CreateMcpWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def create(params)
    CreateMcpStruct.new(id: 'w1', name: params.name, sku: params.sku)
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
  let(:mcp_server) do
    server = CreateMcpSchema.to_mcp_server
    server.server_context = { context: Context.new }
    server
  end

  def call(payload)
    Oj.load(mcp_server.handle_json(Oj.dump(payload)))
  end

  describe 'tools/list' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 'tl-1' }
    end

    let(:tools) { call(request_payload)['result']['tools'] }

    it 'includes a create tool for entity sets that support create' do
      expect(tools).to include(
        'name' => 'create_Widgets',
        'description' => 'Create a new Widgets record',
        'inputSchema' => {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'name' => { 'type' => 'string', 'x-nullable' => true },
            'sku' => { 'type' => 'string' }
          },
          'required' => ['sku']
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
        'params' => { 'name' => 'create_Widgets',
                      'arguments' => { 'name' => 'Gadget', 'sku' => 'SKU1' } },
        'id' => 'tc-1' }
    end

    it 'creates the record and returns it as structured JSON' do
      result = call(request_payload)['result']
      record = Oj.load(result['content'][0]['text'])

      expect(result['isError']).to be(false)
      expect(record).to include('id' => 'w1', 'name' => 'Gadget')
    end

    it 'returns a tool-not-found error for a create tool on a read-only set' do
      request_payload['params']['name'] = 'create_People'

      expect(call(request_payload)['error']['code']).to eq(-32_602)
    end

    it 'returns a tool-not-found error for a search tool on an unknown set' do
      request_payload['params']['name'] = 'search_Unknown'

      expect(call(request_payload)['error']['code']).to eq(-32_602)
    end
  end
end
