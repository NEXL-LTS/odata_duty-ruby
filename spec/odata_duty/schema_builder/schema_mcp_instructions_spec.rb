require 'spec_helper'

class SchemaBuilderMcpInstructionsResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, 'MCP instructions from schema description' do
    def build_schema(&block)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        block&.call(s)
        entity = s.add_entity_type(name: 'McpInstructionsEntity') do |et|
          et.property_ref 'id', String
        end
        s.add_entity_set(name: 'McpInstructionsSet', entity_type: entity,
                         resolver: 'SchemaBuilderMcpInstructionsResolver')
      end
    end

    def initialize_result(schema)
      server = schema.to_mcp_server
      server.server_context = { context: Context.new }
      request = { 'jsonrpc' => '2.0', 'id' => 'i-1', 'method' => 'initialize',
                  'params' => { 'protocolVersion' => '2025-06-18', 'capabilities' => {},
                                'clientInfo' => { 'name' => 'RSpec', 'version' => '0.0.1' } } }
      Oj.load(server.handle_json(Oj.dump(request)))['result']
    end

    it 'reports the schema description as instructions' do
      schema = build_schema { |s| s.description = 'Directory of conference attendees' }
      expect(initialize_result(schema)['instructions'])
        .to eq('Directory of conference attendees')
    end

    it 'omits instructions entirely when the schema has no description' do
      expect(initialize_result(build_schema)).not_to have_key('instructions')
    end
  end
end
