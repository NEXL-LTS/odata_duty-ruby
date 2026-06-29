require 'spec_helper'

class CreateMcpImmutableOrderResolver < OdataDuty::SetResolver
  def create(params)
    Struct.new(:id, :account_number, :note, :created_at)
          .new('o1', params.account_number, params.note, '2026-06-23')
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP create tool with immutable property' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'CreateMcpImmutableOrderEntity') do |et|
          et.property_ref 'id', String, computed: true
          et.property 'account_number', String, nullable: false, mutability: :immutable
          et.property 'note', String
          et.property 'created_at', String, computed: true
        end

        s.add_entity_set(name: 'Orders', entity_type: entity,
                         resolver: 'CreateMcpImmutableOrderResolver')
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
      tools.find { |t| t['name'] == 'create_Orders' }['inputSchema']
    end

    it 'includes the immutable property as settable on create' do
      expect(create_schema['properties']).to include('account_number', 'note')
    end

    it 'lists the non-nullable immutable property as required' do
      expect(create_schema['required']).to include('account_number')
    end

    it 'excludes computed properties from the create schema' do
      expect(create_schema['properties'].keys).not_to include('created_at', 'id')
    end
  end
end
