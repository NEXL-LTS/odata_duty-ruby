require 'spec_helper'

class DeleteMcpWidgetResolver < OdataDuty::SetResolver
  def delete(id)
    OpenStruct.new(id: id)
  end
end

class DeleteMcpPersonResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP delete tool' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'DeleteMcpWidgetEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'sku', String, nullable: false
        end

        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'DeleteMcpWidgetResolver')
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'DeleteMcpPersonResolver')
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
end
