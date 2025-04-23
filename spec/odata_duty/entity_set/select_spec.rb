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

class CollectionSelectTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [SupportsCollectionSelectSet, SelectlessCollectionSet]
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

      it do
        expect_any_instance_of(SupportsCollectionSelectSet)
          .to receive(:od_select).with(%i[id i]).and_call_original
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

      it do
        expect_any_instance_of(SupportsCollectionSelectSet)
          .to receive(:od_select).with(%i[c id]).and_call_original
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

      it do
        expect_any_instance_of(SupportsCollectionSelectSet)
          .to receive(:od_select).with(%i[id i]).and_call_original
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

      it do
        expect_any_instance_of(SupportsCollectionSelectSet)
          .to receive(:od_select).with(%i[c id]).and_call_original
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
  end
end
