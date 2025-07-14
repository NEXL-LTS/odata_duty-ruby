require 'spec_helper'

class SupportsCollectionSearchResolver < OdataDuty::SetResolver
  ALL_RECORDS = [
    { 'id' => '1', 'name' => 'John Doe', 'email' => 'john@example.com',
      'address' => '123 Main St, John, ID', 'c' => OpenStruct.new(s: 'value1') },
    { 'id' => '2', 'name' => 'Jane Smith', 'email' => 'jane@example.com',
      'address' => '456 Oak Ave, Seattle, WA', 'c' => OpenStruct.new(s: 'value2') },
    { 'id' => '3', 'name' => 'Bob Johnson', 'email' => 'bob@bob.com',
      'address' => '789 Pine Rd, Portland, OR', 'c' => OpenStruct.new(s: 'bob') },
    { 'id' => '4', 'name' => 'John Doe', 'email' => 'john@example.com',
      'address' => '123 Main St, Boise, ID', 'c' => OpenStruct.new(s: 'searched') }
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
                  '@odata.id' => 'https://localhost/SupportsCollectionSearch(\'4\')',
                  'id' => '4',
                  'name' => 'John Doe',
                  'email' => 'john@example.com',
                  'address' => '123 Main St, Boise, ID',
                  'c' => { 's' => 'searched' }
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
      end
    end
  end
end
