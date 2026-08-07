require 'spec_helper'

class GetMcpWidget
  attr_reader :id, :name, :sku

  def initialize(id, name, sku)
    @id = id
    @name = name
    @sku = sku
  end

  def self.all
    [new('1', 'First', 'SKU-1'), new('2', 'Second', 'SKU-2')]
  end
end

class GetMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'sku', String, nullable: false
end

class GetMcpWidgetSet < OdataDuty::EntitySet
  entity_type GetMcpWidgetEntity
  name 'People'
  url 'People'

  def od_after_init
    @records = GetMcpWidget.all
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end
end

class GetMcpWriteOnlySet < OdataDuty::EntitySet
  entity_type GetMcpWidgetEntity
  name 'WriteOnly'
  url 'WriteOnly'

  def create(params)
    GetMcpWidget.new('new', params.name, params.sku)
  end
end

class GetMcpIntegerEntity < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'name', String
end

class GetMcpIntegerSet < OdataDuty::EntitySet
  entity_type GetMcpIntegerEntity
  name 'Numbers'
  url 'Numbers'

  def individual(id)
    OpenStruct.new(id: id, name: "n#{id}")
  end
end

class GetMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [GetMcpWidgetSet, GetMcpWriteOnlySet, GetMcpIntegerSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP get tool' do
  let(:mcp_server) do
    server = GetMcpSchema.to_mcp_server
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

    it 'exposes a get tool for a set that implements individual' do
      get_tool = tool('get_People')

      expect(get_tool['description']).to eq('Get a single People record by ID')
      expect(get_tool['inputSchema']['type']).to eq('object')
      expect(get_tool['inputSchema']['required']).to eq(['id'])
      expect(get_tool['inputSchema']['properties']).to eq(
        'id' => { 'type' => 'string', 'readOnly' => true },
        'odata_select' => { 'type' => 'string',
                            'description' => 'Comma-separated properties to return' }
      )
    end

    it 'does not expose a get tool for a set that only implements create' do
      expect(tools.map { |t| t['name'] }).not_to include('get_WriteOnly')
    end
  end

  describe 'tools/call for get' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'get_People', 'arguments' => { 'id' => '1' } }, 'id' => 'tc-1' }
    end

    it 'returns the individual JSON, matching GET /People(\'1\')' do
      result = call(request_payload)['result']
      body = Oj.load(result['content'][0]['text'])

      expect(result['isError']).to be(false)
      expect(body['id']).to eq('1')
      expect(body['name']).to eq('First')
    end

    it 'projects only the selected properties when odata_select is given' do
      request_payload['params']['arguments']['odata_select'] = 'name'
      body = Oj.load(call(request_payload)['result']['content'][0]['text'])

      expect(body).to include('name' => 'First')
      expect(body).not_to have_key('sku')
    end

    it 'surfaces a missing key as a tool error' do
      request_payload['params']['arguments'] = { 'id' => 'nope' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(true)
    end

    it 'surfaces an uncoercible key as a tool error' do
      request_payload['params']['name'] = 'get_Numbers'
      request_payload['params']['arguments'] = { 'id' => 'not-a-number' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(true)
    end
  end
end
