require 'spec_helper'

class SchemaMcpWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class SchemaMcpWidget
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.all
    [new('1', 'First'), new('2', 'Second')]
  end
end

class SchemaMcpSearchableSet < OdataDuty::EntitySet
  entity_type SchemaMcpWidgetEntity
  name 'Searchables'
  url 'Searchables'

  def od_after_init
    @records = SchemaMcpWidget.all
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

  def od_search(_expression)
    @records
  end
end

class SchemaMcpPlainSet < OdataDuty::EntitySet
  entity_type SchemaMcpWidgetEntity
  name 'Plains'
  url 'Plains'

  def collection
    []
  end
end

class SchemaMcpSchema < OdataDuty::Schema
  namespace 'SchemaMcpSpace'
  title 'Schema MCP Service'
  version '2.0.0'
  base_url 'http://localhost:3000/api'
  entity_sets [SchemaMcpSearchableSet, SchemaMcpPlainSet]
end

RSpec.describe OdataDuty::Schema, 'to_mcp_server' do
  let(:mcp_server) do
    server = SchemaMcpSchema.to_mcp_server
    server.server_context = { context: Context.new }
    server
  end

  def call(payload)
    Oj.load(mcp_server.handle_json(Oj.dump(payload)))
  end

  describe 'tools/list' do
    let(:tool_names) do
      request = { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 't-1' }
      call(request)['result']['tools'].map { |t| t['name'] }
    end

    it 'exposes a search tool for a set whose resolver defines od_search' do
      expect(tool_names).to include('search_Searchables')
    end

    it 'does not expose a search tool for a set without od_search' do
      expect(tool_names).not_to include('search_Plains')
    end
  end

  describe 'initialize' do
    it 'reports the schema title and version as server info' do
      request = {
        'jsonrpc' => '2.0', 'id' => 'i-1', 'method' => 'initialize',
        'params' => { 'protocolVersion' => '2025-06-18', 'capabilities' => {},
                      'clientInfo' => { 'name' => 'RSpec', 'version' => '0.0.1' } }
      }

      expect(call(request)['result']['serverInfo']).to eq(
        'name' => 'Schema MCP Service', 'version' => '2.0.0'
      )
    end
  end
end
