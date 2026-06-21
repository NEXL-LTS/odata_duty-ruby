require 'spec_helper'

class CreateMcpWidgetResolver < OdataDuty::SetResolver
  def create(params)
    Struct.new(:id, :name).new('w1', params.name)
  end
end

class CreateMcpPersonResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP create tool' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'CreateMcpWidgetEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'CreateMcpWidgetResolver')
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'CreateMcpPersonResolver')
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

      it 'includes a create tool for entity sets that support create' do
        expect(tools).to include(
          'name' => 'create_Widgets',
          'description' => 'Create a new Widgets record',
          'inputSchema' => {
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
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
          'params' => { 'name' => 'create_Widgets',
                        'arguments' => { 'id' => 'w1', 'name' => 'Gadget' } },
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
end
