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
    end

    describe '#oas_2' do
      let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }
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
            'description' => 'Search across entity contents using structured expressions with AND, OR, NOT operators'
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
  end
end
