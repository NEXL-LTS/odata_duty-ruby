require 'spec_helper'

class ListMcpWidget
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second'), new('3', 'Third')]
  end
end

class ListMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class ListMcpSearchableSet < OdataDuty::EntitySet
  entity_type ListMcpWidgetEntity
  name 'People'
  url 'People'

  def od_after_init
    @records = ListMcpWidget.all
  end

  def collection
    @records
  end

  def od_top(top)
    @records = @records[0...top.to_i]
  end

  def od_skip(skip)
    @records = @records[skip.to_i..]
  end

  def od_search(_expression)
    @records
  end
end

class ListMcpPlainSet < OdataDuty::EntitySet
  entity_type ListMcpWidgetEntity
  name 'Plains'
  url 'Plains'

  def od_after_init
    @records = ListMcpWidget.all
  end

  def collection
    @records
  end
end

class ListMcpWriteOnlySet < OdataDuty::EntitySet
  entity_type ListMcpWidgetEntity
  name 'WriteOnly'
  url 'WriteOnly'

  def create(params)
    ListMcpWidget.new('new', params.name)
  end
end

class ListMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ListMcpSearchableSet, ListMcpPlainSet, ListMcpWriteOnlySet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP list tool' do
  let(:mcp_server) do
    server = ListMcpSchema.to_mcp_server
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

    def tool(name)
      tools.find { |t| t['name'] == name }
    end

    it 'exposes a list tool for a set that implements collection with od_search' do
      list_tool = tool('list_People')

      expect(list_tool['description']).to eq('List People records')
      expect(list_tool['inputSchema']['type']).to eq('object')
      expect(list_tool['inputSchema']['required']).to eq([])
      expect(list_tool['inputSchema']['properties']).to eq(
        'odata_filter' => { 'type' => 'string', 'description' => 'OData $filter expression' },
        'odata_select' => { 'type' => 'string',
                            'description' => 'Comma-separated properties to return' },
        'odata_search' => { 'type' => 'string',
                            'description' => 'Search expression (AND, OR, NOT)' },
        'odata_top' => { 'type' => 'integer', 'description' => 'Max records to return' },
        'odata_skip' => { 'type' => 'integer', 'description' => 'Records to skip' }
      )
    end

    it 'omits odata_search from the input schema when the set does not define od_search' do
      list_tool = tool('list_Plains')

      expect(list_tool['inputSchema']['properties']).not_to have_key('odata_search')
      expect(list_tool['inputSchema']['properties'].keys).to eq(
        %w[odata_filter odata_select odata_top odata_skip]
      )
    end

    it 'does not expose a list tool for a set that only implements create' do
      expect(tools.map { |t| t['name'] }).not_to include('list_WriteOnly')
    end
  end

  describe 'tools/call for list' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'list_People', 'arguments' => {} }, 'id' => 'tc-1' }
    end

    it 'returns the collection JSON, matching GET /People' do
      result = call(request_payload)['result']
      body = Oj.load(result['content'][0]['text'])

      expect(result['isError']).to be(false)
      expect(body['value'].map { |r| r['name'] }).to eq(%w[First Second Third])
    end

    it 'forwards odata_top as the $top OData query option' do
      request_payload['params']['arguments'] = { 'odata_top' => 2 }
      body = Oj.load(call(request_payload)['result']['content'][0]['text'])

      expect(body['value'].map { |r| r['name'] }).to eq(%w[First Second])
    end

    it 'surfaces an odata_select on an undefined property as a tool error' do
      request_payload['params']['arguments'] = { 'odata_select' => 'nonexistent' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(true)
    end

    it 'surfaces a malformed odata_filter as a tool error' do
      request_payload['params']['arguments'] = { 'odata_filter' => 'not a filter' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(true)
    end
  end
end
