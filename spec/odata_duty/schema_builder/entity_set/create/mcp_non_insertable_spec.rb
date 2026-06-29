require 'spec_helper'

class CreateMcpNonInsertableOrderResolver < OdataDuty::SetResolver
  def create(params)
    Struct.new(:id, :status, :note).new('o1', 'open', params.note)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP create tool with non_insertable property' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'CreateMcpNonInsertableOrderEntity') do |et|
          et.property_ref 'id', String, computed: true
          et.property 'status', String, mutability: :non_insertable
          et.property 'note', String
        end

        s.add_entity_set(name: 'Order', entity_type: entity,
                         resolver: 'CreateMcpNonInsertableOrderResolver')
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

    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 'tl-1' }
    end

    let(:tools) { call(request_payload)['result']['tools'] }

    let(:create_schema) do
      tools.find { |t| t['name'] == 'create_Order' }['inputSchema']
    end

    it 'excludes the non_insertable property from the create schema' do
      expect(create_schema['properties'].keys).not_to include('status')
    end

    it 'keeps the read_write property in the create schema' do
      expect(create_schema['properties']).to include('note')
    end
  end
end
