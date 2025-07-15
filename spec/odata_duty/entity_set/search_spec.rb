require 'spec_helper'

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
end
