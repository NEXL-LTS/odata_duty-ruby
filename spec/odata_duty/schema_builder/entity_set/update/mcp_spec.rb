require 'spec_helper'

class UpdateMcpWidgetResolver < OdataDuty::SetResolver
  def update(id, params)
    Struct.new(:id, :name, :sku).new(id, params.name, params.sku)
  end
end

class UpdateMcpPersonResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP update tool' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'UpdateMcpWidgetEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'sku', String, nullable: false
        end

        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'UpdateMcpWidgetResolver')
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'UpdateMcpPersonResolver')
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
end
