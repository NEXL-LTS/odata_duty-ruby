require 'spec_helper'

class SchemaBuilderMcpInstructionsResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class SchemaBuilderMcpInstructionsFullResolver < SchemaBuilderMcpInstructionsResolver
  def od_filter_eq(_property_name, _value)
    []
  end

  def od_search(_expression)
    []
  end

  def od_skiptoken(_skiptoken)
    []
  end
end

class SchemaBuilderMcpInstructionsIndividualOnlyResolver < OdataDuty::SetResolver
  def individual(id)
    OpenStruct.new(id: id)
  end

  def od_filter_eq(_property_name, _value)
    []
  end

  def od_search(_expression)
    []
  end

  def od_skiptoken(_skiptoken)
    []
  end
end

class SchemaBuilderMcpInstructionsFilterResolver < SchemaBuilderMcpInstructionsResolver
  def od_filter_eq(_property_name, _value)
    []
  end
end

class SchemaBuilderMcpInstructionsSearchResolver < SchemaBuilderMcpInstructionsResolver
  def od_search(_expression)
    []
  end
end

class SchemaBuilderMcpInstructionsSkiptokenResolver < SchemaBuilderMcpInstructionsResolver
  def od_skiptoken(_skiptoken)
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, 'MCP instructions' do
    def build_schema(*resolvers, description: nil)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.description = description if description
        entity = s.add_entity_type(name: 'McpInstructionsEntity') do |et|
          et.property_ref 'id', String
        end
        resolvers.each_with_index do |resolver, index|
          s.add_entity_set(name: "McpInstructionsSet#{index}", entity_type: entity,
                           resolver: resolver)
        end
      end
    end

    def instructions_for(schema)
      server = schema.to_mcp_server
      server.server_context = { context: Context.new }
      request = { 'jsonrpc' => '2.0', 'id' => 'i-1', 'method' => 'initialize',
                  'params' => { 'protocolVersion' => '2025-06-18', 'capabilities' => {},
                                'clientInfo' => { 'name' => 'RSpec', 'version' => '0.0.1' } } }
      Oj.load(server.handle_json(Oj.dump(request)))['result']['instructions']
    end

    it 'reports the schema description ahead of the query-option dialect' do
      schema = build_schema('SchemaBuilderMcpInstructionsFullResolver',
                            'SchemaBuilderMcpInstructionsResolver',
                            description: 'Attendee records for the spring conference.')

      expect(instructions_for(schema))
        .to eq("Attendee records for the spring conference.\n\n" \
               "#{ExpectedMcpInstructions::ALL_OPTIONS}")
    end

    it 'reports the dialect alone when the schema has no description' do
      schema = build_schema('SchemaBuilderMcpInstructionsResolver')

      expect(instructions_for(schema)).to eq(ExpectedMcpInstructions::NO_OPTIONS)
    end

    it 'describes $filter only when a set supports filtering' do
      text = instructions_for(build_schema('SchemaBuilderMcpInstructionsFilterResolver'))

      expect(text).to include(ExpectedMcpInstructions::FILTER_LINE)
      expect(text).not_to include(ExpectedMcpInstructions::SEARCH_LINE,
                                  ExpectedMcpInstructions::PAGING_LINE)
    end

    it 'describes $search only when a set defines od_search' do
      text = instructions_for(build_schema('SchemaBuilderMcpInstructionsSearchResolver'))

      expect(text).to include(ExpectedMcpInstructions::SEARCH_LINE)
      expect(text).not_to include(ExpectedMcpInstructions::FILTER_LINE,
                                  ExpectedMcpInstructions::PAGING_LINE)
    end

    it 'omits the query-option lines when only a set without a collection supports them' do
      schema = build_schema('SchemaBuilderMcpInstructionsIndividualOnlyResolver')

      expect(instructions_for(schema)).to eq(ExpectedMcpInstructions::NO_OPTIONS)
    end

    it 'describes paging only when a set defines od_skiptoken' do
      text = instructions_for(build_schema('SchemaBuilderMcpInstructionsSkiptokenResolver'))

      expect(text).to include(ExpectedMcpInstructions::PAGING_LINE)
      expect(text).not_to include(ExpectedMcpInstructions::FILTER_LINE,
                                  ExpectedMcpInstructions::SEARCH_LINE)
    end
  end
end
