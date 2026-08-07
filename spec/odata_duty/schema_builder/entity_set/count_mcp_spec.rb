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

  def od_search(expression)
    pattern = Regexp.union(expression.terms.map(&:to_s))
    @records = @records.select { |r| r.name.match?(pattern) }
  end
end

class CountMcpNoCountResolver < OdataDuty::SetResolver
  def od_after_init
    @records = CountMcpBuilderRecord.all
  end

  def collection
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
        s.add_entity_set(name: 'NoCount', entity_type: entity,
                         resolver: 'CountMcpNoCountResolver')
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
          'odata_filter' => { 'type' => 'string' },
          'odata_search' => { 'type' => 'string' }
        )
      end

      it 'omits odata_search from the input schema when the resolver does not define ' \
         'od_search' do
        count_tool = tool('count_Plains')

        expect(count_tool['inputSchema']['properties']).not_to have_key('odata_search')
        expect(count_tool['inputSchema']['properties']).to eq(
          'odata_filter' => { 'type' => 'string' }
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

      it 'narrows the count with odata_filter' do
        request_payload['params']['arguments'] = { 'odata_filter' => "name eq 'First'" }
        result = call(request_payload)['result']

        expect(result['isError']).to be(false)
        expect(result['content'][0]['text']).to eq('1')
      end

      it 'narrows the count with odata_search' do
        request_payload['params']['arguments'] = { 'odata_search' => 'First' }
        result = call(request_payload)['result']

        expect(result['isError']).to be(false)
        expect(result['content'][0]['text']).to eq('1')
      end

      it 'surfaces a malformed odata_search as a tool error' do
        request_payload['params']['arguments'] = { 'odata_search' => 'apple AND orange OR peach' }
        result = call(request_payload)['result']

        expect(result['isError']).to be(true)
        expect(result['content'][0]['text']).to match(%r{Mixed AND/OR operators are not supported})
      end
    end
  end
end
