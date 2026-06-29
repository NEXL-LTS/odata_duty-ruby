require 'spec_helper'

class UpdateMcpNonInsertableOrderResolver < OdataDuty::SetResolver
  def update(id, params)
    Struct.new(:id, :status, :note).new(id, params.status, params.note)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP update tool with non_insertable property' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'UpdateMcpNonInsertableOrderEntity') do |et|
          et.property_ref 'id', String
          et.property 'status', String, mutability: :non_insertable
          et.property 'note', String
        end

        s.add_entity_set(name: 'Order', entity_type: entity,
                         resolver: 'UpdateMcpNonInsertableOrderResolver')
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

    let(:update_schema) do
      tools.find { |t| t['name'] == 'update_Order' }['inputSchema']
    end

    it 'includes the non_insertable property in the update schema' do
      expect(update_schema['properties']).to include('status')
    end

    it 'keeps the key and read_write properties in the update schema' do
      expect(update_schema['properties']).to include('id', 'note')
      expect(update_schema['required']).to eq(['id'])
    end
  end
end
