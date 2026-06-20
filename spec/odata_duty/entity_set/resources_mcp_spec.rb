require 'spec_helper'

class McpResWidget
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second')]
  end
end

class McpResWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class McpResWidgetSet < OdataDuty::EntitySet
  entity_type McpResWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def od_after_init
    @records = McpResWidget.all
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end

  def count
    @records.count
  end
end

class McpResSchema < OdataDuty::Schema
  namespace 'McpResSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpResWidgetSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP resources' do
  let(:mcp_server) do
    server = McpResSchema.to_mcp_server
    server.server_context = { context: Context.new }
    server
  end

  def call(payload)
    Oj.load(mcp_server.handle_json(Oj.dump(payload)))
  end

  describe 'resources/list' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'resources/list', 'params' => {}, 'id' => 'r-1' }
    end

    it 'returns the count resource' do
      resources = call(request_payload)['result']['resources']

      expect(resources).to include(
        'uri' => 'Widgets/$count',
        'name' => 'Widgets Count',
        'description' => 'Get a count of Widgets records',
        'mimeType' => 'text/plain'
      )
    end
  end

  describe 'resources/templates/list' do
    let(:request_payload) do
      {
        'jsonrpc' => '2.0', 'method' => 'resources/templates/list', 'params' => {}, 'id' => 'r-2'
      }
    end

    let(:templates) do
      call(request_payload)['result']['resourceTemplates'].to_h { |t| [t['uriTemplate'], t] }
    end

    it 'returns the individual-by-id template' do
      expect(templates["Widgets('{id}')"]).to eq(
        'uriTemplate' => "Widgets('{id}')",
        'name' => 'McpResWidgetEntity',
        'description' => 'Retrieve a specific McpResWidgetEntity record by ID',
        'mimeType' => 'application/json'
      )
    end

    it 'returns the paginated collection template' do
      expect(templates['Widgets?$top={top}&$skip={skip}']).to eq(
        'uriTemplate' => 'Widgets?$top={top}&$skip={skip}',
        'name' => 'Paginated Widgets Collection',
        'description' => 'Retrieve paginated Widgets records',
        'mimeType' => 'application/json'
      )
    end
  end

  describe 'resources/read' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'resources/read',
        'params' => { 'uri' => "Widgets('1')" }, 'id' => 'r-3' }
    end

    it 'reads a specific record as OData JSON' do
      contents = call(request_payload)['result']['contents'][0]

      expect(contents['uri']).to eq("Widgets('1')")
      expect(contents['mimeType']).to eq('application/json')
      expect(Oj.load(contents['text'])).to include('id' => '1', 'name' => 'First')
    end

    it 'reads a count resource as a text/plain string' do
      request_payload['params']['uri'] = 'Widgets/$count'

      contents = call(request_payload)['result']['contents'][0]

      expect(contents['uri']).to eq('Widgets/$count')
      expect(contents['mimeType']).to eq('text/plain')
      expect(contents['text']).to eq('2')
    end
  end
end
