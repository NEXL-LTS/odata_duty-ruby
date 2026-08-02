require 'spec_helper'

# The MCP server threads the request `context` (from `server_context[:context]`) through every
# tool call into the same OData execution path the REST endpoints use. This set derives its data
# from that context so a tool call fails unless the real context object is forwarded.
McpContextValue = Struct.new(:marker)

class McpContextEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class McpContextSet < OdataDuty::EntitySet
  entity_type McpContextEntity
  name 'Widgets'
  url 'Widgets'

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: "row-#{context.marker}")]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end

class McpContextSchema < OdataDuty::Schema
  namespace 'McpContextSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpContextSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP tool context threading' do
  let(:mcp_server) do
    server = McpContextSchema.to_mcp_server
    server.server_context = { context: McpContextValue.new('from-context') }
    server
  end

  def call(payload)
    Oj.load(mcp_server.handle_json(Oj.dump(payload)))
  end

  it 'forwards the request context into the tool execution path' do
    request = { 'jsonrpc' => '2.0', 'method' => 'tools/call',
                'params' => { 'name' => 'list_Widgets', 'arguments' => {} }, 'id' => 'c-1' }
    content = call(request)['result']['content'][0]

    expect(content['type']).to eq('text')
    expect(Oj.load(content['text'])['value'].first['name']).to eq('row-from-context')
  end

  it 'returns a text tool-error result when the tool execution raises' do
    request = { 'jsonrpc' => '2.0', 'method' => 'tools/call',
                'params' => { 'name' => 'get_Widgets', 'arguments' => { 'id' => 'missing' } },
                'id' => 'c-2' }
    result = call(request)['result']

    expect(result['isError']).to be(true)
    expect(result['content'][0]['type']).to eq('text')
    expect(result['content'][0]['text']).to include('No such entity')
  end
end
