require 'spec_helper'

class McpInstructionsEntity < OdataDuty::EntityType
  property_ref 'id', String
end

module McpInstructionsCollection
  def collection
    []
  end
end

class McpInstructionsPlainSet < OdataDuty::EntitySet
  include McpInstructionsCollection

  entity_type McpInstructionsEntity
  name 'Plains'
  url 'Plains'
end

class McpInstructionsFullSet < OdataDuty::EntitySet
  include McpInstructionsCollection

  entity_type McpInstructionsEntity
  name 'Fulls'
  url 'Fulls'

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

class McpInstructionsFilterSet < OdataDuty::EntitySet
  include McpInstructionsCollection

  entity_type McpInstructionsEntity
  name 'Filters'
  url 'Filters'

  def od_filter_eq(_property_name, _value)
    []
  end
end

class McpInstructionsSearchSet < OdataDuty::EntitySet
  include McpInstructionsCollection

  entity_type McpInstructionsEntity
  name 'Searches'
  url 'Searches'

  def od_search(_expression)
    []
  end
end

class McpInstructionsSkiptokenSet < OdataDuty::EntitySet
  include McpInstructionsCollection

  entity_type McpInstructionsEntity
  name 'Skiptokens'
  url 'Skiptokens'

  def od_skiptoken(_skiptoken)
    []
  end
end

class McpInstructionsIndividualOnlySet < OdataDuty::EntitySet
  entity_type McpInstructionsEntity
  name 'IndividualOnlys'
  url 'IndividualOnlys'

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

class McpInstructionsDescribedSchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  description 'Attendee records for the spring conference.'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsFullSet, McpInstructionsPlainSet]
end

class McpInstructionsPlainSchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsPlainSet]
end

class McpInstructionsFilterSchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsFilterSet]
end

class McpInstructionsSearchSchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsSearchSet]
end

class McpInstructionsSkiptokenSchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsSkiptokenSet]
end

class McpInstructionsIndividualOnlySchema < OdataDuty::Schema
  namespace 'McpInstructionsSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [McpInstructionsIndividualOnlySet]
end

RSpec.describe OdataDuty::Schema, 'MCP instructions' do
  def instructions_for(schema)
    server = schema.to_mcp_server
    server.server_context = { context: Context.new }
    request = { 'jsonrpc' => '2.0', 'id' => 'i-1', 'method' => 'initialize',
                'params' => { 'protocolVersion' => '2025-06-18', 'capabilities' => {},
                              'clientInfo' => { 'name' => 'RSpec', 'version' => '0.0.1' } } }
    Oj.load(server.handle_json(Oj.dump(request)))['result']['instructions']
  end

  it 'reports the schema description ahead of the query-option dialect' do
    expect(instructions_for(McpInstructionsDescribedSchema))
      .to eq("Attendee records for the spring conference.\n\n" \
             "#{ExpectedMcpInstructions::ALL_OPTIONS}")
  end

  it 'reports the dialect alone when the schema has no description' do
    expect(instructions_for(McpInstructionsPlainSchema))
      .to eq(ExpectedMcpInstructions::NO_OPTIONS)
  end

  it 'describes $filter only when a set supports filtering' do
    text = instructions_for(McpInstructionsFilterSchema)

    expect(text).to include(ExpectedMcpInstructions::FILTER_LINE)
    expect(text).not_to include(ExpectedMcpInstructions::SEARCH_LINE,
                                ExpectedMcpInstructions::PAGING_LINE)
  end

  it 'describes $search only when a set defines od_search' do
    text = instructions_for(McpInstructionsSearchSchema)

    expect(text).to include(ExpectedMcpInstructions::SEARCH_LINE)
    expect(text).not_to include(ExpectedMcpInstructions::FILTER_LINE,
                                ExpectedMcpInstructions::PAGING_LINE)
  end

  it 'omits the query-option lines when only a set without a collection supports them' do
    expect(instructions_for(McpInstructionsIndividualOnlySchema))
      .to eq(ExpectedMcpInstructions::NO_OPTIONS)
  end

  it 'describes paging only when a set defines od_skiptoken' do
    text = instructions_for(McpInstructionsSkiptokenSchema)

    expect(text).to include(ExpectedMcpInstructions::PAGING_LINE)
    expect(text).not_to include(ExpectedMcpInstructions::FILTER_LINE,
                                ExpectedMcpInstructions::SEARCH_LINE)
  end
end
