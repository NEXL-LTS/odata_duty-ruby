require 'spec_helper'

class CreateMcpImmutableStruct
  attr_reader :id, :account_number, :note, :created_at

  def initialize(id:, account_number:, note:)
    @id = id
    @account_number = account_number
    @note = note
    @created_at = '2026-06-23'
  end
end

class CreateMcpImmutableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: true
  property 'account_number', String, nullable: false, mutability: :immutable
  property 'note', String
  property 'created_at', String, computed: true
end

class CreateMcpImmutableOrderSet < OdataDuty::EntitySet
  entity_type CreateMcpImmutableOrderEntity
  name 'Orders'
  url 'Orders'

  def create(params)
    CreateMcpImmutableStruct.new(id: 'o1', account_number: params.account_number,
                                 note: params.note)
  end
end

class CreateMcpImmutableSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CreateMcpImmutableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP create tool with immutable property' do
  let(:mcp_server) do
    server = CreateMcpImmutableSchema.to_mcp_server
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
