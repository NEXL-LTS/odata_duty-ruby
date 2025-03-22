require 'spec_helper'

class SupportsCollectionSelectResolver < OdataDuty::SetResolver
  ALL_RECORDS = (1..2).map do |i|
    { 'id' => i.to_s, 'i' => i, 't' => Time.at(i), 'c' => OpenStruct.new(s: i.to_s) }
  end
  SELECTED_RECORDS = (1..2).map do |i| # used to prove od_select is called
    { 'id' => i.to_s, 'i' => i + 2, 't' => Time.at(i + 2), 'c' => OpenStruct.new(s: (i + 2).to_s) }
  end

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_select(select)
    keys = select.map(&:to_s) + ['id']
    @records = SELECTED_RECORDS.map { |r| r.slice(*keys) }
  end

  def collection
    @records.map { |r| CamelSnakeStruct.new(r) }
  end

  def individual(id)
    collection.find { |r| r.id == id }
  end
end

class SelectlessCollectionResolver < OdataDuty::SetResolver
  ALL_RECORDS = (1..2).map do |i|
    CamelSnakeStruct.new('id' => i.to_s, 'i' => i, 't' => Time.at(i),
                         'c' => CamelSnakeStruct.new('s' => i.to_s))
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

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can select specific properties in the return result' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        complex = s.add_entity_type(name: 'CollectionSelectTestComplex') do |et|
          et.property 's', String
        end

        entity = s.add_entity_type(name: 'CollectionSelectTest') do |et|
          et.property_ref 'id', String
          et.property 'i', Integer
          et.property 't', Time
          et.property 'c', complex
        end

        s.add_entity_set(entity_type: entity, resolver: 'SelectlessCollectionResolver')
        s.add_entity_set(entity_type: entity, resolver: 'SupportsCollectionSelectResolver')
      end
    end

    describe '#execute' do
      describe 'individual' do
        it do
          json_string = schema.execute("SelectlessCollection('1')",
                                       context: Context.new,
                                       query_options: { '$select' => 'id,i' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SelectlessCollection/$entity',
              '@odata.id' => 'SelectlessCollection(\'1\')',
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
              '@odata.context' => '$metadata#SelectlessCollection/$entity',
              '@odata.id' => 'SelectlessCollection(\'1\')',
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
          json_string = schema.execute("SupportsCollectionSelect('1')",
                                       context: Context.new,
                                       query_options: { '$select' => 'id,i' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SupportsCollectionSelect/$entity',
              '@odata.id' => 'SupportsCollectionSelect(\'1\')',
              'id' => '1', 'i' => 3
            }
          )
        end

        it do
          json_string = schema.execute("SupportsCollectionSelect('1')",
                                       context: Context.new,
                                       query_options: { '$select' => 'c' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SupportsCollectionSelect/$entity',
              '@odata.id' => 'SupportsCollectionSelect(\'1\')',
              'c' => { 's' => '3' }
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
              '@odata.context' => '$metadata#SelectlessCollection',
              'value' => [{ '@odata.id' => 'SelectlessCollection(\'1\')',
                            'id' => '1', 'i' => 1 },
                          { '@odata.id' => 'SelectlessCollection(\'2\')',
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
              '@odata.context' => '$metadata#SelectlessCollection',
              'value' => [{ '@odata.id' => 'SelectlessCollection(\'1\')',
                            'c' => { 's' => '1' } },
                          { '@odata.id' => 'SelectlessCollection(\'2\')',
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
          json_string = schema.execute('SupportsCollectionSelect',
                                       context: Context.new,
                                       query_options: { '$select' => 'id,i' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SupportsCollectionSelect',
              'value' => [{ '@odata.id' => 'SupportsCollectionSelect(\'1\')',
                            'id' => '1', 'i' => 3 },
                          { '@odata.id' => 'SupportsCollectionSelect(\'2\')',
                            'id' => '2', 'i' => 4 }]
            }
          )
        end

        it do
          json_string = schema.execute('SupportsCollectionSelect',
                                       context: Context.new,
                                       query_options: { '$select' => 'c' })
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SupportsCollectionSelect',
              'value' => [{ '@odata.id' => 'SupportsCollectionSelect(\'1\')',
                            'c' => { 's' => '3' } },
                          { '@odata.id' => 'SupportsCollectionSelect(\'2\')',
                            'c' => { 's' => '4' } }]
            }
          )
        end
      end
    end
  end
end
