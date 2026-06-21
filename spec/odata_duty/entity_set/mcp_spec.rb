require 'spec_helper'

class McpInitWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class McpInitWidgetSet < OdataDuty::EntitySet
  entity_type McpInitWidgetEntity
  name 'Widgets'
  url 'Widgets'
end

class McpInitSchema < OdataDuty::Schema
  namespace 'McpInitSpace'
  title 'This is a sample OData service.'
  version '1.2.3'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInitWidgetSet]
end

RSpec.describe OdataDuty::EntitySet, 'MCP initialize' do
  subject(:server) { McpInitSchema.to_mcp_server }

  describe 'initialize' do
    let(:request_payload) do
      {
        'jsonrpc' => '2.0',
        'id' => 'init-1',
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => protocol_version,
          'capabilities' => {},
          'clientInfo' => { 'name' => 'RSpecClient', 'version' => '0.0.1' }
        }
      }
    end

    context 'with a supported protocol version' do
      let(:protocol_version) { '2025-06-18' }

      it 'negotiates the requested version and echoes capabilities and serverInfo' do
        response = Oj.load(server.handle_json(Oj.dump(request_payload)))

        expect(response['result']).to eq(
          'protocolVersion' => '2025-06-18',
          'capabilities' => { 'tools' => {}, 'resources' => {} },
          'serverInfo' => { 'name' => 'This is a sample OData service.', 'version' => '1.2.3' }
        )
      end
    end

    context 'with an unsupported protocol version' do
      let(:protocol_version) { '1999-01-01' }

      it 'falls back to the latest supported version' do
        response = Oj.load(server.handle_json(Oj.dump(request_payload)))

        expect(response['result']['protocolVersion']).to eq('2025-11-25')
      end
    end
  end

  describe 'unknown method' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'id' => 'u-1', 'method' => 'does/not/exist', 'params' => {} }
    end

    it 'returns a -32601 error' do
      response = Oj.load(server.handle_json(Oj.dump(request_payload)))

      expect(response['error']['code']).to eq(-32_601)
    end
  end

  describe 'notifications/initialized' do
    let(:request_payload) do
      { 'jsonrpc' => '2.0', 'method' => 'notifications/initialized', 'params' => {} }
    end

    it 'returns no response' do
      expect(server.handle_json(Oj.dump(request_payload))).to be_nil
    end
  end
end
