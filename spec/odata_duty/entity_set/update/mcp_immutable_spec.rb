require 'spec_helper'

class UpdateMcpImmutableStruct
  attr_reader :id, :account_number, :note, :created_at

  def initialize(id:, note:)
    @id = id
    @account_number = 'acct-fixed'
    @note = note
    @created_at = '2026-06-23'
  end
end

class UpdateMcpImmutableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'account_number', String, nullable: false, mutability: :immutable
  property 'note', String
  property 'created_at', String, computed: true
end

class UpdateMcpImmutableOrderSet < OdataDuty::EntitySet
  entity_type UpdateMcpImmutableOrderEntity
  name 'Orders'
  url 'Orders'

  def update(id, params)
    UpdateMcpImmutableStruct.new(id: id, note: params.note)
  end
end

class UpdateMcpImmutableSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UpdateMcpImmutableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP update tool with immutable property' do
  let(:mcp_server) do
    server = UpdateMcpImmutableSchema.to_mcp_server
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
