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
    @records = @records.select do |key_val|
      key_val.values.any? do |v|
        v.to_s.include?(search_expression)
      end
    end
  end

  def collection
    @records.map { |r| CamelSnakeStruct.new(r) }
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
          .to receive(:od_search).with('Boise').and_call_original
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
    end
  end
end
