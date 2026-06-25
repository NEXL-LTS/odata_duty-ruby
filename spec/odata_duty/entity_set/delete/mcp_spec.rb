require 'spec_helper'

class DeleteMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'sku', String, nullable: false
end

class DeleteMcpWidgetSet < OdataDuty::EntitySet
  entity_type DeleteMcpWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def delete(id)
    OpenStruct.new(id: id)
  end
end

class DeleteMcpPersonSet < OdataDuty::EntitySet
  entity_type DeleteMcpWidgetEntity
  name 'People'
  url 'People'
end

class DeleteMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [DeleteMcpWidgetSet, DeleteMcpPersonSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP delete tool' do
  let(:mcp_server) do
    server = DeleteMcpSchema.to_mcp_server
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

    it 'includes a delete tool for entity sets that support delete' do
      expect(tools).to include(
        'name' => 'delete_Widgets',
        'description' => 'Delete an existing Widgets record',
        'inputSchema' => {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'id' => { 'type' => 'string', 'readOnly' => true }
          },
          'required' => ['id']
        }
      )
    end

    it 'does not include a delete tool for read-only entity sets' do
      expect(tools.map { |t| t['name'] }).not_to include('delete_People')
    end
  end

  describe 'tools/call for delete' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'delete_Widgets', 'arguments' => { 'id' => 'w1' } },
        'id' => 'tc-1' }
    end

    it 'deletes the record and returns an acknowledgement without an entity payload' do
      result = call(request_payload)['result']
      payload = Oj.load(result['content'][0]['text'])

      expect(result['isError']).to be(false)
      expect(payload).not_to include('id')
    end

    it 'returns a tool-not-found error for a delete tool on a read-only set' do
      request_payload['params']['name'] = 'delete_People'

      expect(call(request_payload)['error']['code']).to eq(-32_602)
    end
  end
end
