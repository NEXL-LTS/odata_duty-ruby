require 'spec_helper'

class UpdateMcpStruct
  attr_reader :id, :name, :sku

  def initialize(id:, name:, sku:)
    @id = id
    @name = name
    @sku = sku
  end
end

class UpdateMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'sku', String, nullable: false
end

class UpdateMcpWidgetSet < OdataDuty::EntitySet
  entity_type UpdateMcpWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def update(id, params)
    UpdateMcpStruct.new(id: id, name: params.name, sku: params.sku)
  end
end

class UpdateMcpPersonSet < OdataDuty::EntitySet
  entity_type UpdateMcpWidgetEntity
  name 'People'
  url 'People'
end

class UpdateMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UpdateMcpWidgetSet, UpdateMcpPersonSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP update tool' do
  let(:mcp_server) do
    server = UpdateMcpSchema.to_mcp_server
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

    it 'includes an update tool for entity sets that support update' do
      expect(tools).to include(
        'name' => 'update_Widgets',
        'description' => 'Update an existing Widgets record',
        'inputSchema' => {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'id' => { 'type' => 'string', 'readOnly' => true },
            'name' => { 'type' => 'string', 'x-nullable' => true },
            'sku' => { 'type' => 'string' }
          },
          'required' => ['id']
        }
      )
    end

    it 'does not include an update tool for read-only entity sets' do
      expect(tools.map { |t| t['name'] }).not_to include('update_People')
    end
  end

  describe 'tools/call for update' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'update_Widgets',
                      'arguments' => { 'id' => 'w1', 'name' => 'Updated', 'sku' => 'SKU1' } },
        'id' => 'tc-1' }
    end

    it 'updates the record and returns it as structured JSON' do
      result = call(request_payload)['result']
      record = Oj.load(result['content'][0]['text'])

      expect(result['isError']).to be(false)
      expect(record).to include('id' => 'w1', 'name' => 'Updated')
    end

    it 'returns a tool-not-found error for an update tool on a read-only set' do
      request_payload['params']['name'] = 'update_People'

      expect(call(request_payload)['error']['code']).to eq(-32_602)
    end
  end
end
