require 'spec_helper'

class CollectionSelectTestComplexEntity < OdataDuty::ComplexType
  property 's', String
end

class CollectionSelectTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'i', Integer
  property 't', Time
  property 'c', CollectionSelectTestComplexEntity
end

class SupportsCollectionSelectSet < OdataDuty::EntitySet
  entity_type CollectionSelectTestEntity

  ALL_RECORDS = (1..2).map do |i|
    { 'id' => i.to_s, 'i' => i, 't' => Time.at(i), 'c' => CamelSnakeStruct.new('s' => i.to_s) }
  end

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_select(select)
    keys = select.map(&:to_s)
    @records = @records.map { |r| r.slice(*keys) }
  end

  def collection
    @records.map { |r| CamelSnakeStruct.new(r) }
  end

  def individual(id)
    collection.find { |r| r.id == id }
  end
end

class SelectlessCollectionSet < OdataDuty::EntitySet
  entity_type CollectionSelectTestEntity

  ALL_RECORDS = (1..2).map do |i|
    CamelSnakeStruct.new('id' => i.to_s, 'i' => i, 't' => Time.at(i),
                         'c' => OpenStruct.new(s: i.to_s))
  end

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

class CapturingSelectSet < OdataDuty::EntitySet
  entity_type CollectionSelectTestEntity

  class << self
    attr_accessor :captured_select
  end

  ALL_RECORDS = SupportsCollectionSelectSet::ALL_RECORDS

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_select(select)
    self.class.captured_select = select
    keys = select.map(&:to_s)
    @records = @records.map { |r| r.slice(*keys) }
  end

  def collection
    @records.map { |r| CamelSnakeStruct.new(r) }
  end

  def individual(id)
    collection.find { |r| r.id == id }
  end
end

class CollectionSelectTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [SupportsCollectionSelectSet, SelectlessCollectionSet, CapturingSelectSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can specific individual result' do
  subject(:schema) { CollectionSelectTestSchema }

  describe '#execute' do
    describe 'individual' do
      it do
        json_string = schema.execute("SelectlessCollection('1')",
                                     context: Context.new,
                                     query_options: { '$select' => 'id,i' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SelectlessCollection/$entity',
            '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'1\')',
            'id' => '1', 'i' => 1
          }
        )
      end

      it do
        json_string = schema.execute("SelectlessCollection('1')",
                                     context: Context.new,
                                     query_options: { '$select' => 'c' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SelectlessCollection/$entity',
            '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'1\')',
            'c' => { 's' => '1' }
          }
        )
      end

      it do
        expect do
          schema.execute("SelectlessCollection('1')",
                         context: Context.new,
                         query_options: { '$select' => 'id,a' })
        end.to raise_error(OdataDuty::UnknownPropertyError)
      end

      it do
        expect do
          schema.execute("SelectlessCollection('1')",
                         context: Context.new,
                         query_options: { '$select' => 'id,c/s' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError)
      end

      it do
        expect do
          schema.execute("SelectlessCollection('1')",
                         context: Context.new,
                         query_options: { '$select' => '"id"' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError)
      end

      it 'returns only the selected properties for an individual' do
        json_string = schema.execute("SupportsCollectionSelect('1')",
                                     context: Context.new,
                                     query_options: { '$select' => 'id,i' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSelect/$entity',
            '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'1\')',
            'id' => '1', 'i' => 1
          }
        )
      end

      it 'returns only the selected complex property for an individual' do
        json_string = schema.execute("SupportsCollectionSelect('1')",
                                     context: Context.new,
                                     query_options: { '$select' => 'c' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSelect/$entity',
            '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'1\')',
            'c' => { 's' => '1' }
          }
        )
      end
    end

    describe 'collection' do
      it do
        json_string = schema.execute('SelectlessCollection',
                                     context: Context.new,
                                     query_options: { '$select' => 'id,i' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SelectlessCollection',
            'value' => [{ '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'1\')',
                          'id' => '1', 'i' => 1 },
                        { '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'2\')',
                          'id' => '2', 'i' => 2 }]
          }
        )
      end

      it do
        json_string = schema.execute('SelectlessCollection',
                                     context: Context.new,
                                     query_options: { '$select' => 'c' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SelectlessCollection',
            'value' => [{ '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'1\')',
                          'c' => { 's' => '1' } },
                        { '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'2\')',
                          'c' => { 's' => '2' } }]
          }
        )
      end

      it do
        expect do
          schema.execute('SelectlessCollection',
                         context: Context.new,
                         query_options: { '$select' => 'id,a' })
        end.to raise_error(OdataDuty::UnknownPropertyError)
      end

      it do
        expect do
          schema.execute('SelectlessCollection',
                         context: Context.new,
                         query_options: { '$select' => 'id,c/s' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError)
      end

      it do
        expect do
          schema.execute('SelectlessCollection',
                         context: Context.new,
                         query_options: { '$select' => '"id"' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError)
      end

      it 'returns only the selected properties for a collection' do
        json_string = schema.execute('SupportsCollectionSelect',
                                     context: Context.new,
                                     query_options: { '$select' => 'id,i' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSelect',
            'value' => [{ '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'1\')',
                          'id' => '1', 'i' => 1 },
                        { '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'2\')',
                          'id' => '2', 'i' => 2 }]
          }
        )
      end

      it 'returns only the selected complex property for a collection' do
        json_string = schema.execute('SupportsCollectionSelect',
                                     context: Context.new,
                                     query_options: { '$select' => 'c' })
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollectionSelect',
            'value' => [{ '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'1\')',
                          'c' => { 's' => '1' } },
                        { '@odata.id' => 'http://localhost:3000/api/SupportsCollectionSelect(\'2\')',
                          'c' => { 's' => '2' } }]
          }
        )
      end
    end

    describe 'parsing and hook payload' do
      it 'strips leading and trailing whitespace around each comma-separated name' do
        json_string = schema.execute('SelectlessCollection',
                                     context: Context.new,
                                     query_options: { '$select' => ' id , i ' })
        response = Oj.load(json_string)
        expect(response['value']).to eq(
          [{ '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'1\')',
             'id' => '1', 'i' => 1 },
           { '@odata.id' => 'http://localhost:3000/api/SelectlessCollection(\'2\')',
             'id' => '2', 'i' => 2 }]
        )
      end

      it 'treats a nil $select value as no selection' do
        json_string = schema.execute('SelectlessCollection',
                                     context: Context.new,
                                     query_options: { '$select' => nil })
        response = Oj.load(json_string)
        expect(response['value'].first).to include('id' => '1', 'i' => 1)
      end

      it 'raises InvalidQueryOptionError with an exact message for a malformed name' do
        expect do
          schema.execute('SelectlessCollection', context: Context.new,
                                                 query_options: { '$select' => 'first-name' })
        end.to raise_error(OdataDuty::InvalidQueryOptionError,
                           "The property 'first-name' is not valid")
      end

      it 'raises UnknownPropertyError with an exact message for an undeclared name' do
        expect do
          schema.execute('SelectlessCollection', context: Context.new,
                                                 query_options: { '$select' => 'a' })
        end.to raise_error(OdataDuty::UnknownPropertyError,
                           "The property 'a' does not exist")
      end

      entity_defined_at = "#{__FILE__}:7"

      it 'makes the first backtrace entry the entity type definition location for invalid names' do
        head =
          begin
            schema.execute('SelectlessCollection', context: Context.new,
                                                   query_options: { '$select' => 'first-name' })
            nil
          rescue OdataDuty::InvalidQueryOptionError => e
            e.backtrace.first
          end
        expect(head).to eq(entity_defined_at)
      end

      it 'makes the first backtrace entry the entity type definition location for unknown names' do
        head =
          begin
            schema.execute('SelectlessCollection', context: Context.new,
                                                   query_options: { '$select' => 'a' })
            nil
          rescue OdataDuty::UnknownPropertyError => e
            e.backtrace.first
          end
        expect(head).to eq(entity_defined_at)
      end

      it 'passes selected names plus refs, deduplicated, when $select is present' do
        schema.execute('CapturingSelect', context: Context.new,
                                          query_options: { '$select' => 'id, i' })
        expect(CapturingSelectSet.captured_select).to eq(%i[id i])
      end

      it 'passes all property names plus refs, deduplicated, when $select is absent' do
        schema.execute('CapturingSelect', context: Context.new, query_options: {})
        expect(CapturingSelectSet.captured_select).to eq(%i[id i t c])
      end

      it 'passes the selected complex property plus refs, deduplicated' do
        schema.execute('CapturingSelect', context: Context.new,
                                          query_options: { '$select' => 'c' })
        expect(CapturingSelectSet.captured_select).to eq(%i[c id])
      end
    end
  end
end
