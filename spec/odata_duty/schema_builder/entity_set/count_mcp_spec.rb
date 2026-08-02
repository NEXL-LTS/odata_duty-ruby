require 'spec_helper'

class CountMcpBuilderRecord
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second'), new('3', 'Third')]
  end
end

class CountMcpSearchableResolver < OdataDuty::SetResolver
  def od_after_init
    @records = CountMcpBuilderRecord.all
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

  def od_search(_expression)
    @records
  end
end

class CountMcpPlainResolver < OdataDuty::SetResolver
  def od_after_init
    @records = CountMcpBuilderRecord.all
  end

  def collection
    @records
  end

  def count
    @records.size
  end
end

class CountMcpWriteOnlyResolver < OdataDuty::SetResolver
  def create(params)
    CountMcpBuilderRecord.new('new', params.name)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP count tool' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'CountMcpBuilderEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'CountMcpSearchableResolver')
        s.add_entity_set(name: 'Plains', entity_type: entity,
                         resolver: 'CountMcpPlainResolver')
        s.add_entity_set(name: 'WriteOnly', entity_type: entity,
                         resolver: 'CountMcpWriteOnlyResolver')
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

      it 'omits $search from the input schema when the resolver does not define od_search' do
        count_tool = tool('count_Plains')

        expect(count_tool['inputSchema']['properties']).not_to have_key('$search')
        expect(count_tool['inputSchema']['properties']).to eq(
          '$filter' => { 'type' => 'string' }
        )
      end

      it 'does not expose a count tool for a set that only implements create' do
        expect(tools.map { |t| t['name'] }).not_to include('count_WriteOnly')
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

      it 'returns a count without error when $search is supplied' do
        request_payload['params']['arguments'] = { '$search' => 'First' }
        result = call(request_payload)['result']

        expect(result['isError']).to be(false)
        expect(result['content'][0]['text']).to eq('3')
      end
    end
  end
end
