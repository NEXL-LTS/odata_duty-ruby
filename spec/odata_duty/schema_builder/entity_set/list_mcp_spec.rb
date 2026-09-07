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

module ListMcpBuilderRecords
  def od_after_init
    @records = ListMcpBuilderRecord.all
  end

  def collection
    @records
  end
end

class ListMcpSearchableResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  def od_top(top)
    @records = @records[0...top.to_i]
  end

  def od_skip(skip)
    @records = @records[skip.to_i..]
  end

  def od_skiptoken(skiptoken)
    @records = @records.drop_while { |r| r.id <= skiptoken.to_s }
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def od_search(_expression)
    @records
  end
end

class ListMcpPlainResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords
end

class ListMcpFilterOrOnlyResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  def od_filter_or(predicates)
    @records = @records.select { |r| predicates.any? { |p| p.value == r.name } }
  end
end

class ListMcpPrivateFilterResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  private

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end
end

class ListMcpTopOnlyResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  def od_top(top)
    @records = @records[0...top.to_i]
  end
end

class ListMcpSkipOnlyResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  def od_skip(skip)
    @records = @records[skip.to_i..]
  end
end

class ListMcpSkiptokenOnlyResolver < OdataDuty::SetResolver
  include ListMcpBuilderRecords

  def od_skiptoken(skiptoken)
    @records = @records.drop_while { |r| r.id <= skiptoken.to_s }
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
        s.add_entity_set(name: 'FilterOrs', entity_type: entity,
                         resolver: 'ListMcpFilterOrOnlyResolver')
        s.add_entity_set(name: 'PrivateFilters', entity_type: entity,
                         resolver: 'ListMcpPrivateFilterResolver')
        s.add_entity_set(name: 'Tops', entity_type: entity,
                         resolver: 'ListMcpTopOnlyResolver')
        s.add_entity_set(name: 'Skips', entity_type: entity,
                         resolver: 'ListMcpSkipOnlyResolver')
        s.add_entity_set(name: 'Skiptokens', entity_type: entity,
                         resolver: 'ListMcpSkiptokenOnlyResolver')
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

      it 'exposes a list tool for a resolver that implements every read query-option hook' do
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
          'odata_skip' => { 'type' => 'integer', 'description' => 'Records to skip' },
          'odata_skiptoken' => { 'type' => 'string' }
        )
      end

      it 'advertises only odata_select for a resolver with no query-option hooks' do
        list_tool = tool('list_Plains')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_select])
      end

      it 'advertises odata_filter for a resolver whose only filter hook is od_filter_or' do
        list_tool = tool('list_FilterOrs')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_filter odata_select])
      end

      it 'ignores a private od_filter_ hook when deciding whether to advertise odata_filter' do
        list_tool = tool('list_PrivateFilters')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_select])
      end

      it 'advertises odata_top only for a resolver defining od_top' do
        list_tool = tool('list_Tops')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_select odata_top])
      end

      it 'advertises odata_skip only for a resolver defining od_skip' do
        list_tool = tool('list_Skips')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_select odata_skip])
      end

      it 'advertises odata_skiptoken only for a resolver defining od_skiptoken' do
        list_tool = tool('list_Skiptokens')

        expect(list_tool['inputSchema']['properties'].keys).to eq(%w[odata_select odata_skiptoken])
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

      it 'forwards odata_skiptoken as the $skiptoken OData query option' do
        request_payload['params']['arguments'] = { 'odata_skiptoken' => '1' }
        body = Oj.load(call(request_payload)['result']['content'][0]['text'])

        expect(body['value'].map { |r| r['name'] }).to eq(%w[Second Third])
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

      it 'surfaces a negative odata_top (an Integer, as MCP forwards it) as a tool error' do
        request_payload['params']['arguments'] = { 'odata_top' => -1 }
        result = call(request_payload)['result']

        expect(result['isError']).to be(true)
      end

      it 'surfaces a negative odata_skip (an Integer, as MCP forwards it) as a tool error' do
        request_payload['params']['arguments'] = { 'odata_skip' => -1 }
        result = call(request_payload)['result']

        expect(result['isError']).to be(true)
      end
    end
  end
end
