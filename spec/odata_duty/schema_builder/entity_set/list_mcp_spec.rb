require 'spec_helper'

class ListMcpBuilderRecord
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second'), new('3', 'Third')]
  end
end

class ListMcpSearchableResolver < OdataDuty::SetResolver
  def od_after_init
    @records = ListMcpBuilderRecord.all
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

class ListMcpPlainResolver < OdataDuty::SetResolver
  def od_after_init
    @records = ListMcpBuilderRecord.all
  end

  def collection
    @records
  end
end

class ListMcpWriteOnlyResolver < OdataDuty::SetResolver
  def create(params)
    ListMcpBuilderRecord.new('new', params.name)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP list tool' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'ListMcpBuilderEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'ListMcpSearchableResolver')
        s.add_entity_set(name: 'Plains', entity_type: entity,
                         resolver: 'ListMcpPlainResolver')
        s.add_entity_set(name: 'WriteOnly', entity_type: entity,
                         resolver: 'ListMcpWriteOnlyResolver')
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
          '$filter' => { 'type' => 'string', 'description' => 'OData $filter expression' },
          '$select' => { 'type' => 'string',
                         'description' => 'Comma-separated properties to return' },
          '$search' => { 'type' => 'string',
                         'description' => 'Search expression (AND, OR, NOT)' },
          '$top' => { 'type' => 'integer', 'description' => 'Max records to return' },
          '$skip' => { 'type' => 'integer', 'description' => 'Records to skip' }
        )
      end

      it 'omits $search from the input schema when the resolver does not define od_search' do
        list_tool = tool('list_Plains')

        expect(list_tool['inputSchema']['properties']).not_to have_key('$search')
        expect(list_tool['inputSchema']['properties'].keys).to eq(
          ['$filter', '$select', '$top', '$skip']
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

      it 'forwards $top verbatim as an OData query option' do
        request_payload['params']['arguments'] = { '$top' => 2 }
        body = Oj.load(call(request_payload)['result']['content'][0]['text'])

        expect(body['value'].map { |r| r['name'] }).to eq(%w[First Second])
      end

      it 'surfaces an $select on an undefined property as a tool error' do
        request_payload['params']['arguments'] = { '$select' => 'nonexistent' }
        result = call(request_payload)['result']

        expect(result['isError']).to be(true)
      end

      it 'surfaces a malformed $filter as a tool error' do
        request_payload['params']['arguments'] = { '$filter' => 'not a filter' }
        result = call(request_payload)['result']

        expect(result['isError']).to be(true)
      end
    end
  end
end
