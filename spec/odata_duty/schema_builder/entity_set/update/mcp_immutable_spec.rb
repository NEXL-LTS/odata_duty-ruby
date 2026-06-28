require 'spec_helper'

class UpdateMcpImmutableOrderResolver < OdataDuty::SetResolver
  def update(id, params)
    Struct.new(:id, :account_number, :note, :created_at)
          .new(id, 'acct-fixed', params.note, '2026-06-23')
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP update tool with immutable property' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'UpdateMcpImmutableOrderEntity') do |et|
          et.property_ref 'id', String
          et.property 'account_number', String, nullable: false, mutability: :immutable
          et.property 'note', String
          et.property 'created_at', String, computed: true
        end

        s.add_entity_set(name: 'Orders', entity_type: entity,
                         resolver: 'UpdateMcpImmutableOrderResolver')
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
      tools.find { |t| t['name'] == 'update_Orders' }['inputSchema']
    end

    it 'excludes the immutable property from the update schema' do
      expect(update_schema['properties'].keys).not_to include('account_number')
    end

    it 'excludes computed properties from the update schema' do
      expect(update_schema['properties'].keys).not_to include('created_at')
    end

    it 'keeps the key and read_write properties in the update schema' do
      expect(update_schema['properties']).to include('id', 'note')
      expect(update_schema['required']).to eq(['id'])
    end
  end
end
