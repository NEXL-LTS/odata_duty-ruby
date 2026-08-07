require 'spec_helper'

class SupportsCollectionSearchResolver < OdataDuty::SetResolver
  ALL_RECORDS = [
    { 'id' => '1', 'name' => 'Alice Brown', 'email' => 'alice@example.com',
      'address' => '123 Main St, Boise, ID', 'c' => OpenStruct.new(s: 'value1') },
    { 'id' => '2', 'name' => 'Bob Smith', 'email' => 'bob@example.com',
      'address' => '456 Oak Ave, Seattle, WA', 'c' => OpenStruct.new(s: 'value2') },
    { 'id' => '3', 'name' => 'Charlie Johnson', 'email' => 'charlie@portland.com',
      'address' => '789 Pine Rd, Portland, OR', 'c' => OpenStruct.new(s: 'value3') },
    { 'id' => '4', 'name' => 'Dave Wilson', 'email' => 'dave@example.com',
      'address' => '321 Elm St, Denver, CO', 'c' => OpenStruct.new(s: 'searched') }
  ].freeze

  def od_after_init
    @records = ALL_RECORDS
  end

  class << self
    attr_accessor :last_search_and, :last_search_or, :last_search_terms
  end

  def od_search(search_expression)
    self.class.last_search_and = search_expression.and?
    self.class.last_search_or = search_expression.or?
    self.class.last_search_terms = search_expression.terms.map(&:to_s)
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

class SearchlessCollectionResolver < OdataDuty::SetResolver
  ALL_RECORDS = [
    CamelSnakeStruct.new('id' => '1', 'name' => 'John Doe', 'email' => 'john@example.com',
                         'address' => 'Main St, Boise, ID',
                         'c' => CamelSnakeStruct.new('s' => 'value1')),
    CamelSnakeStruct.new('id' => '2', 'name' => 'Jane Smith', 'email' => 'jane@example.com',
                         'address' => 'Oak Ave, Seattle, WA',
                         'c' => CamelSnakeStruct.new('s' => 'value2')),
    CamelSnakeStruct.new('id' => '3', 'name' => 'Bob Johnson', 'email' => 'bob@boise.com',
                         'address' => 'Pine Rd, Portland, OR',
                         'c' => CamelSnakeStruct.new('s' => 'boise'))
  ].freeze

  def od_after_init
    @records = ALL_RECORDS
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can search through collection results' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        complex = s.add_entity_type(name: 'CollectionSearchTestComplex') do |et|
          et.property 's', String
        end

        entity = s.add_entity_type(name: 'CollectionSearchTest') do |et|
          et.property_ref 'id', String
          et.property 'name', String
          et.property 'email', String
          et.property 'address', String
          et.property 'c', complex
        end

        s.add_entity_set(entity_type: entity, resolver: 'SearchlessCollectionResolver')
        s.add_entity_set(entity_type: entity, resolver: 'SupportsCollectionSearchResolver')
      end
    end

    describe '#execute' do
      describe 'collection' do
        it 'searches collection with matching term' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Boise' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => 'https://localhost/$metadata#SupportsCollectionSearch',
              'value' => [
                {
                  '@odata.id' => 'https://localhost/SupportsCollectionSearch(\'1\')',
                  'id' => '1',
                  'name' => 'Alice Brown',
                  'email' => 'alice@example.com',
                  'address' => '123 Main St, Boise, ID',
                  'c' => { 's' => 'value1' }
                }
              ]
            }
          )
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
                                       query_options: { '$search' => 'Boise',
                                                        '$select' => 'id,name' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first).to include('id', 'name')
          expect(response['value'].first).not_to include('address', 'email')
        end

        # Test comprehensive search expression parsing functionality
        it 'parses single word search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Alice' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first['name']).to eq('Alice Brown')
        end

        it 'parses quoted phrase search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => '"Alice Brown"' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first['name']).to eq('Alice Brown')
        end

        it 'parses negated term search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'NOT Alice' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(3)
          names = response['value'].map { |v| v['name'] }
          expect(names).to contain_exactly('Bob Smith', 'Charlie Johnson', 'Dave Wilson')
        end

        it 'parses implicit AND search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Alice Brown' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first['name']).to eq('Alice Brown')
        end

        it 'parses explicit AND search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Alice AND Brown' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first['name']).to eq('Alice Brown')
        end

        it 'parses OR expression search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Alice OR Bob' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(2)
          names = response['value'].map { |v| v['name'] }
          expect(names).to contain_exactly('Alice Brown', 'Bob Smith')
        end

        it 'parses OR with negation' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => 'Alice OR NOT example.com' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(2)
          names = response['value'].map { |v| v['name'] }
          expect(names).to contain_exactly('Alice Brown', 'Charlie Johnson')
        end

        it 'handles empty search string' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => '' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(4)
        end

        it 'handles whitespace only search' do
          json_string = schema.execute('SupportsCollectionSearch',
                                       context: Context.new,
                                       query_options: { '$search' => '   ' })
          response = Oj.load(json_string)
          expect(response['value'].length).to eq(4)
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
          end.to raise_error(OdataDuty::NoImplementationError)
        end

        it 'raises error for unterminated quote' do
          expect do
            schema.execute('SupportsCollectionSearch',
                           context: Context.new,
                           query_options: { '$search' => '"hello world' })
          end.to raise_error(OdataDuty::InvalidQueryOptionError)
        end

        it 'raises error for implicit AND mixed with OR' do
          expect do
            schema.execute('SupportsCollectionSearch',
                           context: Context.new,
                           query_options: { '$search' => 'apple orange OR peach' })
          end.to raise_error(OdataDuty::NoImplementationError,
                             %r{Mixed AND/OR operators are not supported})
        end
      end

      describe 'the search expression handed to od_search' do
        def search(value)
          SupportsCollectionSearchResolver.last_search_and = nil
          SupportsCollectionSearchResolver.last_search_or = nil
          SupportsCollectionSearchResolver.last_search_terms = nil
          schema.execute('SupportsCollectionSearch', context: Context.new,
                                                     query_options: { '$search' => value })
        end

        it 'hands an empty AND expression for an empty search string' do
          search('')
          expect(SupportsCollectionSearchResolver.last_search_terms).to eq([])
          expect(SupportsCollectionSearchResolver.last_search_and).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_or).to be(false)
        end

        it 'hands an empty AND expression for a whitespace-only search string' do
          search('   ')
          expect(SupportsCollectionSearchResolver.last_search_terms).to eq([])
          expect(SupportsCollectionSearchResolver.last_search_and).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_or).to be(false)
        end

        it 'flags an OR expression as or? and not and?' do
          search('Alice OR Bob')
          expect(SupportsCollectionSearchResolver.last_search_or).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_and).to be(false)
        end

        it 'flags a single term as and? and not or?' do
          search('Alice')
          expect(SupportsCollectionSearchResolver.last_search_and).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_or).to be(false)
        end

        it 'flags an implicit AND expression as and? and not or?' do
          search('Alice Brown')
          expect(SupportsCollectionSearchResolver.last_search_and).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_or).to be(false)
        end

        it 'flags an explicit AND expression as and? and not or?' do
          search('Alice AND Brown')
          expect(SupportsCollectionSearchResolver.last_search_and).to be(true)
          expect(SupportsCollectionSearchResolver.last_search_or).to be(false)
        end

        it 'renders negated and quoted terms back to their search syntax' do
          search('NOT "old data" AND hello')
          expect(SupportsCollectionSearchResolver.last_search_terms)
            .to eq(['NOT "old data"', 'hello'])
        end

        it 'ignores surrounding whitespace' do
          search('  Alice  ')
          padded_terms = SupportsCollectionSearchResolver.last_search_terms
          search('Alice')
          expect(padded_terms).to eq(SupportsCollectionSearchResolver.last_search_terms)
        end
      end

      describe 'malformed search input' do
        def search(value)
          schema.execute('SupportsCollectionSearch', context: Context.new,
                                                     query_options: { '$search' => value })
        end

        it 'raises for a lone opening parenthesis' do
          expect { search('(hello') }
            .to raise_error(OdataDuty::NoImplementationError, /Parentheses are not supported/)
        end

        it 'raises for a lone closing parenthesis' do
          expect { search('hello)') }
            .to raise_error(OdataDuty::NoImplementationError, /Parentheses are not supported/)
        end

        it 'raises an invalid query error for unparseable input containing only AND' do
          expect { search('hello AND foo!') }
            .to raise_error(OdataDuty::InvalidQueryOptionError,
                            /\AInvalid search expression: .*char \d/)
        end

        it 'raises an invalid query error for unparseable input containing only OR' do
          expect { search('foo! OR hello') }
            .to raise_error(OdataDuty::InvalidQueryOptionError,
                            /\AInvalid search expression: .*char \d/)
        end

        it 'raises for an explicit AND tree whose terms include the literal word OR' do
          expect { search('a AND OR AND b') }
            .to raise_error(OdataDuty::NoImplementationError,
                            %r{Mixed AND/OR operators are not supported})
        end
      end
    end

    describe '#metadata' do
      let(:metadata_xml) { schema.metadata_xml }

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
        searchless_entity_set_xml = metadata_xml
                                    .split('<EntitySet Name="SearchlessCollection"')[1]
                                    .split('</EntitySet>')[0]
        expect(searchless_entity_set_xml).not_to include('Capabilities.SearchRestrictions')
      end
    end

    describe 'mcp' do
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
          { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 'tools-list-1' }
        end

        def tool_named(name)
          call(request_payload)['result']['tools'].find { |tool| tool['name'] == name }
        end

        it 'exposes odata_search through the list tool for entity sets that support search' do
          properties = tool_named('list_SupportsCollectionSearch')['inputSchema']['properties']
          expect(properties).to include('odata_search')
        end

        it 'omits odata_search from the list tool for entity sets that do not support search' do
          properties = tool_named('list_SearchlessCollection')['inputSchema']['properties']
          expect(properties).not_to include('odata_search')
        end

        it 'no longer advertises a standalone search tool' do
          tool_names = call(request_payload)['result']['tools'].map { |tool| tool['name'] }
          expect(tool_names).not_to include('search_SupportsCollectionSearch')
          expect(tool_names).not_to include('search_SearchlessCollection')
        end
      end

      describe 'tools/call list with odata_search' do
        let(:request_payload) do
          { 'jsonrpc' => '2.0', 'method' => 'tools/call',
            'params' => { 'name' => 'list_SupportsCollectionSearch',
                          'arguments' => { 'odata_search' => 'Alice' } },
            'id' => 'tools-call-1' }
        end

        def search_value(payload)
          Oj.load(call(payload)['result']['content'][0]['text'])
        end

        it 'executes search through the list tool' do
          result = call(request_payload)['result']
          response = Oj.load(result['content'][0]['text'])

          expect(result['isError']).to be(false)
          expect(response['value']).to be_an(Array)
          expect(response['value'].length).to eq(1)
          expect(response['value'].first['name']).to eq('Alice Brown')
          expect(response['@odata.context']).to include('SupportsCollectionSearch')
        end

        it 'supports complex search expressions' do
          request_payload['params']['arguments']['odata_search'] = 'Alice OR Bob'
          response = search_value(request_payload)

          expect(response['value'].length).to eq(2)
          names = response['value'].map { |v| v['name'] }
          expect(names).to contain_exactly('Alice Brown', 'Bob Smith')
        end

        it 'returns a tool-not-found error for the removed search tool' do
          request_payload['params']['name'] = 'search_SupportsCollectionSearch'

          expect(call(request_payload)['error']['code']).to eq(-32_602)
        end

        it 'returns a tool-not-found error for an unknown tool' do
          request_payload['params']['name'] = 'unknown_tool'

          expect(call(request_payload)['error']['code']).to eq(-32_602)
        end

        it 'returns a tool-error result for search expression parsing errors' do
          request_payload['params']['arguments']['odata_search'] = 'apple AND orange OR peach'

          result = call(request_payload)['result']
          expect(result['isError']).to be(true)
          expect(result['content'][0]['text'])
            .to match(%r{Mixed AND/OR operators are not supported})
        end
      end
    end
  end
end
