require 'spec_helper'

class CreateMcpNonInsertableStruct
  attr_reader :id, :status, :note

  def initialize(id:, note:)
    @id = id
    @status = 'open'
    @note = note
  end
end

class CreateMcpNonInsertableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: true
  property 'status', String, mutability: :non_insertable
  property 'note', String
end

class CreateMcpNonInsertableOrderSet < OdataDuty::EntitySet
  entity_type CreateMcpNonInsertableOrderEntity
  name 'Order'
  url 'Order'

  def create(params)
    CreateMcpNonInsertableStruct.new(id: 'o1', note: params.note)
  end
end

class CreateMcpNonInsertableSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CreateMcpNonInsertableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP create tool with non_insertable property' do
  let(:mcp_server) do
    server = CreateMcpNonInsertableSchema.to_mcp_server
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
