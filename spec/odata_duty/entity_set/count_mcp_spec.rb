require 'spec_helper'

class CountMcpWidget
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second'), new('3', 'Third')]
  end
end

class CountMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class CountMcpSearchableSet < OdataDuty::EntitySet
  entity_type CountMcpWidgetEntity
  name 'People'
  url 'People'

  def od_after_init
    @records = CountMcpWidget.all
  end

  def collection
    @records
  end

  def count
    @records.size
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def od_search(expression)
    terms = expression.terms.map(&:to_s)
    @records = @records.select { |r| terms.any? { |t| r.name.include?(t) } }
  end
end

class CountMcpNoCountSet < OdataDuty::EntitySet
  entity_type CountMcpWidgetEntity
  name 'NoCount'
  url 'NoCount'

  def od_after_init
    @records = CountMcpWidget.all
  end

  def collection
    @records
  end
end

class CountMcpPlainSet < OdataDuty::EntitySet
  entity_type CountMcpWidgetEntity
  name 'Plains'
  url 'Plains'

  def od_after_init
    @records = CountMcpWidget.all
  end

  def collection
    @records
  end

  def count
    @records.size
  end
end

class CountMcpWriteOnlySet < OdataDuty::EntitySet
  entity_type CountMcpWidgetEntity
  name 'WriteOnly'
  url 'WriteOnly'

  def create(params)
    CountMcpWidget.new('new', params.name)
  end
end

class CountMcpSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CountMcpSearchableSet, CountMcpNoCountSet, CountMcpPlainSet, CountMcpWriteOnlySet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP count tool' do
  let(:mcp_server) do
    server = CountMcpSchema.to_mcp_server
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

    it 'exposes a count tool for a set that implements collection with od_search' do
      count_tool = tool('count_People')

      expect(count_tool['description']).to eq('Count People records')
      expect(count_tool['inputSchema']['type']).to eq('object')
      expect(count_tool['inputSchema']['required']).to eq([])
      expect(count_tool['inputSchema']['properties']).to eq(
        '$filter' => { 'type' => 'string' },
        '$search' => { 'type' => 'string' }
      )
    end

    it 'omits $search from the input schema when the set does not define od_search' do
      count_tool = tool('count_Plains')

      expect(count_tool['inputSchema']['properties']).not_to have_key('$search')
      expect(count_tool['inputSchema']['properties']).to eq(
        '$filter' => { 'type' => 'string' }
      )
    end

    it 'does not expose a count tool for a set that only implements create' do
      expect(tools.map { |t| t['name'] }).not_to include('count_WriteOnly')
    end

    it 'does not expose a count tool for a set that implements collection but not count' do
      tool_names = tools.map { |t| t['name'] }
      expect(tool_names).to include('list_NoCount')
      expect(tool_names).not_to include('count_NoCount')
    end
  end

  describe 'tools/call for count' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'tools/call',
        'params' => { 'name' => 'count_People', 'arguments' => {} }, 'id' => 'tc-1' }
    end

    it 'returns the count as text' do
      result = call(request_payload)['result']

      expect(result['isError']).to be(false)
      expect(result['content'][0]['text']).to eq('3')
    end

    it 'narrows the count with $filter' do
      request_payload['params']['arguments'] = { '$filter' => "name eq 'First'" }
      result = call(request_payload)['result']

      expect(result['isError']).to be(false)
      expect(result['content'][0]['text']).to eq('1')
    end

    it 'narrows the count with $search' do
      request_payload['params']['arguments'] = { '$search' => 'First' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(false)
      expect(result['content'][0]['text']).to eq('1')
    end

    it 'surfaces a malformed $search as a tool error' do
      request_payload['params']['arguments'] = { '$search' => 'apple AND orange OR peach' }
      result = call(request_payload)['result']

      expect(result['isError']).to be(true)
      expect(result['content'][0]['text']).to match(%r{Mixed AND/OR operators are not supported})
    end
  end
end
