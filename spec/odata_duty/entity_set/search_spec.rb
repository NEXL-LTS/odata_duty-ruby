require 'spec_helper'

# OAS2 test resolver classes
class SupportsCollectionSearchResolver < OdataDuty::SetResolver
  def od_search(search_expression)
    # This method indicates search support for OAS2
  end

  def collection
    []
  end
end

class SearchlessCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class CollectionSearchTestComplexEntity < OdataDuty::ComplexType
  property 's', String
end

class CollectionSearchTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'email', String
  property 'address', String
  property 'c', CollectionSearchTestComplexEntity
end

class SupportsCollectionSearchSet < OdataDuty::EntitySet
  entity_type CollectionSearchTestEntity

  ALL_RECORDS = [
    { 'id' => '1', 'name' => 'John Doe', 'email' => 'john@example.com',
      'address' => '123 Main St, Boise, ID', 'c' => CamelSnakeStruct.new('s' => 'value1') },
    { 'id' => '2', 'name' => 'Jane Smith', 'email' => 'jane@example.com',
      'address' => '456 Oak Ave, Seattle, WA', 'c' => CamelSnakeStruct.new('s' => 'value2') },
    { 'id' => '3', 'name' => 'Bob Johnson', 'email' => 'bob@portland.com',
      'address' => '789 Pine Rd, Portland, OR', 'c' => CamelSnakeStruct.new('s' => 'value3') }
  ].freeze

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_search(search_expression)
    if search_expression.or?
      od_search_or(search_expression)
    else
      od_search_and(search_expression)
    end
  end

  def collection
    @records.map { |r| CamelSnakeStruct.new(r) }
  end

  private

  def od_search_or(search_expression)
    found_records = []
    search_expression.terms.each do |term|
      matches = @records.select do |record|
        match_found = record.values.any? { |v| v.to_s.downcase.include?(term.value.downcase) }
        term.not? ? !match_found : match_found
      end
      found_records += matches
    end
    @records = found_records.uniq { |r| r['id'] }
  end

  def od_search_and(search_expression)
    search_expression.terms.each do |term|
      @records = @records.select do |record|
        match_found = record.values.any? { |v| v.to_s.downcase.include?(term.value.downcase) }
        term.not? ? !match_found : match_found
      end
    end
  end
end

class SearchlessCollectionSet < OdataDuty::EntitySet
  entity_type CollectionSearchTestEntity

  ALL_RECORDS = [
    CamelSnakeStruct.new('id' => '1', 'name' => 'John Doe', 'email' => 'john@example.com',
                         'address' => 'Main St, Boise, ID', 'c' => OpenStruct.new(s: 'value1')),
    CamelSnakeStruct.new('id' => '2', 'name' => 'Jane Smith', 'email' => 'jane@example.com',
                         'address' => 'Oak Ave, Seattle, WA', 'c' => OpenStruct.new(s: 'value2')),
    CamelSnakeStruct.new('id' => '3', 'name' => 'Bob Johnson', 'email' => 'bob@portland.com',
                         'address' => 'Pine Rd, Portland, OR', 'c' => OpenStruct.new(s: 'value3'))
  ].freeze

  def od_after_init
    @records = ALL_RECORDS
  end

  def collection
    @records
  end
end

class CollectionSearchTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [SupportsCollectionSearchSet, SearchlessCollectionSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can search through collection results' do
  subject(:schema) { CollectionSearchTestSchema }

  describe '#execute' do
    describe 'collection' do
      it 'searches collection with matching term' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'Doe' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSearch',
            'value' => [
              {
                '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSearch(\'1\')',
                'id' => '1',
                'name' => 'John Doe',
                'email' => 'john@example.com',
                'address' => '123 Main St, Boise, ID',
                'c' => { 's' => 'value1' }
              }
            ]
          }
        )
      end

      it 'returns empty results when no matches found' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'nonexistent' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSearch',
            'value' => []
          }
        )
      end

      it 'calls od_search method when implemented' do
        expect_any_instance_of(SupportsCollectionSearchSet)
          .to receive(:od_search).with(instance_of(OdataDuty::SearchExpression)).and_call_original
        schema.execute('SupportsCollectionSearch',
                       context: Context.new,
                       query_options: { '$search' => 'Boise' })
      end

      it 'raises error when od_search not implemented' do
        expect do
          schema.execute('SearchlessCollection',
                         context: Context.new,
                         query_options: { '$search' => 'Boise' })
        end.to raise_error(OdataDuty::NoImplementationError, /\$search not implemented/)
      end

      it 'combines search with other query options' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'example.com',
                                                      '$select' => 'id,name,email' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        expect(response['value'].first).to include('id', 'name', 'email')
        expect(response['value'].first).not_to include('address')
      end

      it 'supports AND search expressions' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'John AND Doe' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('John Doe')
      end

      it 'supports OR search expressions' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'John OR Portland' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        names = response['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('John Doe', 'Bob Johnson')
      end

      it 'supports NOT search expressions' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'example.com AND NOT John' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('Jane Smith')
      end

      it 'supports quoted phrases' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => '"Jane Smith"' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('Jane Smith')
      end

      it 'raises error for mixed AND/OR operators' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => 'apple AND orange OR peach' })
        end.to raise_error(OdataDuty::NoImplementationError,
                           %r{Mixed AND/OR operators are not supported})
      end

      it 'raises error for parentheses' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => '(apple AND orange) AND peach' })
        end.to raise_error(OdataDuty::NoImplementationError, /Parentheses are not supported/)
      end

      it 'raises error for implicit AND mixed with OR' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => 'apple orange OR peach' })
        end.to raise_error(OdataDuty::NoImplementationError,
                           %r{Mixed AND/OR operators are not supported})
      end

      # Test comprehensive search expression parsing functionality
      it 'parses single word search' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'Doe' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('John Doe')
      end

      it 'parses negated single term' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'NOT Doe' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        names = response['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('Jane Smith', 'Bob Johnson')
      end

      it 'parses negated quoted phrase' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'NOT "Jane Smith"' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        names = response['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('John Doe', 'Bob Johnson')
      end

      it 'parses implicit AND with multiple terms' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'John Doe' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('John Doe')
      end

      it 'parses explicit AND with multiple terms' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'John AND Doe' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(1)
        expect(response['value'].first['name']).to eq('John Doe')
      end

      it 'parses OR with quoted phrases' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => '"John Doe" OR "Jane Smith"' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        names = response['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('John Doe', 'Jane Smith')
      end

      it 'parses OR with negation' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => 'John OR NOT example.com' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(2)
        names = response['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('John Doe', 'Bob Johnson')
      end

      it 'handles empty search string' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => '' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(3)
      end

      it 'handles whitespace only search' do
        json_string = schema.execute('SupportsCollectionSearch',
                                     context: Context.new,
                                     query_options: { '$search' => '   ' })
        response = Oj.load(json_string)
        expect(response['value'].length).to eq(3)
      end

      it 'raises error for unterminated quote' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => '"hello world' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError)
      end

      it 'raises error for complex mixed operators' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => 'hello OR world AND test' })
        end.to raise_error(OdataDuty::NoImplementationError,
                           %r{Mixed AND/OR operators are not supported})
      end

      it 'raises error for simple parentheses' do
        expect do
          schema.execute('SupportsCollectionSearch',
                         context: Context.new,
                         query_options: { '$search' => '(apple)' })
        end.to raise_error(OdataDuty::NoImplementationError, /Parentheses are not supported/)
      end
    end
  end

  describe '#oas_2' do
    let(:oas2_schema) do
      OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                     base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'CollectionSearchTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'email', String
          et.property 'address', String
        end

        s.add_entity_set(name: 'SupportsCollectionSearch', entity_type: entity,
                         resolver: 'SupportsCollectionSearchResolver')
        s.add_entity_set(name: 'SearchlessCollection', entity_type: entity,
                         resolver: 'SearchlessCollectionResolver')
      end
    end

    let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }
    let(:get_parameters) { json['paths'][path]['get']['parameters'] }
    let(:hashed_parameters) do
      get_parameters.to_h do |p|
        [p['name'], p.slice('type', 'in', 'description')]
      end
    end

    describe '/SupportsCollectionSearch' do
      let(:path) { '/SupportsCollectionSearch' }

      it 'includes $search parameter when od_search is supported' do
        expect(hashed_parameters['$search']).to eq(
          'type' => 'string',
          'in' => 'query',
          'description' => 'Search using structured expressions with AND, OR, NOT operators'
        )
      end

      it 'includes $filter parameter whose description mentions or' do
        expect(hashed_parameters['$filter']).to eq(
          'type' => 'string',
          'in' => 'query',
          'description' => 'Filter the results, supporting `and` and flat `or` combinations'
        )
      end

      it 'includes other standard parameters' do
        expect(hashed_parameters.keys).to include('$filter', '$select', '$search')
      end
    end

    describe '/SearchlessCollection' do
      let(:path) { '/SearchlessCollection' }

      it 'does not include $search parameter when od_search is not supported' do
        expect(hashed_parameters.keys).not_to include('$search')
      end

      it 'includes other standard parameters' do
        expect(hashed_parameters.keys).to include('$filter', '$select')
      end
    end
  end

  describe '#metadata' do
    let(:metadata_xml) do
      OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                     base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'CollectionSearchTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'email', String
          et.property 'address', String
        end

        s.add_entity_set(name: 'SupportsCollectionSearch', entity_type: entity,
                         resolver: 'SupportsCollectionSearchResolver')
        s.add_entity_set(name: 'SearchlessCollection', entity_type: entity,
                         resolver: 'SearchlessCollectionResolver')
      end.metadata_xml
    end

    it 'includes OData Capabilities vocabulary reference' do
      expect(metadata_xml).to include('Org.OData.Capabilities.V1')
      expect(metadata_xml).to include('Alias="Capabilities"')
    end

    it 'includes SearchRestrictions annotation for search-enabled entity sets' do
      expect(metadata_xml).to include('<EntitySet Name="SupportsCollectionSearch"')
      expect(metadata_xml).to include('Term="Capabilities.SearchRestrictions"')
      expect(metadata_xml).to include('Property="Searchable" Bool="true"')
      expect(metadata_xml).to include(
        'Property="UnsupportedExpressions" EnumMember="Capabilities.SearchExpressions/group"'
      )
    end

    it 'does not include SearchRestrictions annotation for non-search entity sets' do
      searchless_entity_set_xml = metadata_xml.split(
        '<EntitySet Name="SearchlessCollection"'
      )[1].split('</EntitySet>')[0]
      expect(searchless_entity_set_xml).not_to include('Capabilities.SearchRestrictions')
    end
  end

  describe 'mcp' do
    let(:mcp_server) { schema }

    describe 'tools/list' do
      let(:request_payload) do
        {
          'jsonrpc' => '2.0',
          'method' => 'tools/list',
          'params' => {},
          'id' => 'tools-list-1'
        }
      end

      it 'returns search tools for entity sets that support search' do
        actual = Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))

        expect(actual['result']['tools']).to include(
          {
            'name' => 'search_SupportsCollectionSearch',
            'description' =>
            'Search SupportsCollectionSearch using expressions with AND, OR, NOT operators',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                '$search' => {
                  'type' => 'string',
                  'description' => 'Search query using expressions with AND, OR, NOT operators'
                }
              },
              'required' => ['$search']
            }
          }
        )
      end

      it 'does not return search tools for entity sets that do not support search' do
        actual = Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))

        tool_names = actual['result']['tools'].map { |tool| tool['name'] }
        expect(tool_names).not_to include('search_SearchlessCollection')
      end
    end

    describe 'tools/call for search' do
      let(:request_payload) do
        {
          'jsonrpc' => '2.0',
          'method' => 'tools/call',
          'params' => {
            'name' => 'search_SupportsCollectionSearch',
            'arguments' => {
              '$search' => 'Doe'
            }
          },
          'id' => 'tools-call-1'
        }
      end

      it 'executes search on entity set that supports search' do
        actual = Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))

        expect(actual['result']['value']).to be_an(Array)
        expect(actual['result']['value'].length).to eq(1)
        expect(actual['result']['value'].first['name']).to eq('John Doe')
        expect(actual['result']['@odata.context']).to include('SupportsCollectionSearch')
      end

      it 'supports complex search expressions' do
        request_payload['params']['arguments']['$search'] = 'Doe OR Jane'

        actual = Oj.load(mcp_server.handle_jsonrpc(request_payload, context: Context.new))

        expect(actual['result']['value']).to be_an(Array)
        expect(actual['result']['value'].length).to eq(2)
        names = actual['result']['value'].map { |v| v['name'] }
        expect(names).to contain_exactly('John Doe', 'Jane Smith')
      end

      it 'raises error for entity set that does not support search' do
        request_payload['params']['name'] = 'search_SearchlessCollection'

        expect do
          mcp_server.handle_jsonrpc(request_payload, context: Context.new)
        end.to raise_error(OdataDuty::NoImplementationError)
      end

      it 'raises error for unknown tool' do
        request_payload['params']['name'] = 'unknown_tool'

        expect do
          mcp_server.handle_jsonrpc(request_payload, context: Context.new)
        end.to raise_error(/Unknown tool/)
      end

      it 'handles search expression parsing errors' do
        request_payload['params']['arguments']['$search'] = 'apple AND orange OR peach'

        expect do
          mcp_server.handle_jsonrpc(request_payload, context: Context.new)
        end.to raise_error(%r{Mixed AND/OR operators are not supported})
      end
    end
  end
end
