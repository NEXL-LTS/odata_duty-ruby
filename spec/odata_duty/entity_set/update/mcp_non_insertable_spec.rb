require 'spec_helper'

class UpdateMcpNonInsertableStruct
  attr_reader :id, :status, :note

  def initialize(id:, status:, note:)
    @id = id
    @status = status
    @note = note
  end
end

class UpdateMcpNonInsertableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'status', String, mutability: :non_insertable
  property 'note', String
end

class UpdateMcpNonInsertableOrderSet < OdataDuty::EntitySet
  entity_type UpdateMcpNonInsertableOrderEntity
  name 'Order'
  url 'Order'

  def update(id, params)
    UpdateMcpNonInsertableStruct.new(id: id, status: params.status, note: params.note)
  end
end

class UpdateMcpNonInsertableSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UpdateMcpNonInsertableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP update tool with non_insertable property' do
  let(:mcp_server) do
    server = UpdateMcpNonInsertableSchema.to_mcp_server
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
