require 'spec_helper'

class CollectionTestEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class SupportsCollectionSet < OdataDuty::EntitySet
  entity_type CollectionTestEntity

  def collection
    [OpenStruct.new(id: '1')]
  end
end

class LargeCollectionSet < OdataDuty::EntitySet
  entity_type CollectionTestEntity

  ALL_RECORDS = (1..102).map { |i| OpenStruct.new(id: i.to_s) }

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_top(top)
    @records = @records[0..top.to_i - 1]
  end

  def od_skiptoken(skiptoken)
    @skiptoken = skiptoken
    @records = @records[skiptoken.to_i..]
  end

  def od_filter_id_ne(value)
    @records = @records.reject { |r| r.id == value }
  end

  def count
    @records.count
  end

  def collection
    max_results = 50
    if @records.count > max_results
      od_next_link_skiptoken(@skiptoken.to_i + max_results)
      @records[@skiptoken.to_i, max_results]
    else
      @records
    end
  end
end

class DoesNotSupportCollectionSet < OdataDuty::EntitySet
  entity_type CollectionTestEntity
end

class CollectionTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [SupportsCollectionSet, DoesNotSupportCollectionSet, LargeCollectionSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can specific individual result' do
  subject(:schema) { CollectionTestSchema }

  describe '#execute' do
    describe 'collection' do
      it do
        json_string = schema.execute('SupportsCollection', context: Context.new)
        response = Oj.load(json_string)
        expect(response).to eq(
          {
            '@odata.context' => 'http://localhost:3000/api/$metadata#SupportsCollection',
            'value' => [
              '@odata.id' => 'http://localhost:3000/api/SupportsCollection(\'1\')',
              'id' => '1'
            ]
          }
        )
      end

      context 'when top is not supported' do
        it do
          expect do
            schema.execute('SupportsCollection', context: Context.new,
                                                 query_options: { '$top' => '1' })
          end.to raise_error(OdataDuty::NoImplementationError,
                             '$top not implemented for SupportsCollectionSet')
        end
      end

      context 'when skip is not supported' do
        it do
          expect do
            schema.execute('SupportsCollection', context: Context.new,
                                                 query_options: { '$skip' => '1' })
          end.to raise_error(OdataDuty::NoImplementationError,
                             '$skip not implemented for SupportsCollectionSet')
        end
      end

      context 'when skiptoken is not supported' do
        it do
          expect do
            schema.execute('SupportsCollection', context: Context.new,
                                                 query_options: { '$skiptoken' => '1' })
          end.to raise_error(OdataDuty::NoImplementationError,
                             '$skiptoken not implemented for SupportsCollectionSet')
        end
      end

      context 'when filter is not supported' do
        it do
          expect do
            schema.execute('SupportsCollection', context: Context.new,
                                                 query_options: { '$filter' => 'id = 1' })
          end.to raise_error(OdataDuty::NoImplementationError)
        end
      end

      it do
        expect do
          schema.execute('DoesNotSupportCollection', context: Context.new)
        end.to raise_error(OdataDuty::NoImplementationError)
      end

      it do
        json_string = schema.execute('LargeCollection', context: Context.new)
        response = Oj.load(json_string)
        context = response['@odata.context']
        expect(context).to eq('http://localhost:3000/api/$metadata#LargeCollection')
        expect(response['value'].count).to eq(50)
        next_link = response['@odata.nextLink']
        expect(next_link).to eq('http://localhost:3000/api/LargeCollection?%24skiptoken=50')
      end

      it do
        json_string = schema.execute('LargeCollection/$count', context: Context.new)
        expect(json_string).to eq(102)
      end

      it do
        json_string = schema.execute('LargeCollection/$count',
                                     context: Context.new,
                                     query_options: { '$filter' => "id ne '1'", '$top' => '1' })
        expect(json_string).to eq(101)
      end

      context 'server side paging' do
        it do
          json_string = schema.execute('LargeCollection', context: Context.new,
                                                          query_options: { '$count' => 'true' })
          response = Oj.load(json_string)
          context = response['@odata.context']
          expect(context).to eq('http://localhost:3000/api/$metadata#LargeCollection')
          expect(response['value'].count).to eq(50)
          next_link = response['@odata.nextLink']
          expect(next_link).to eq('http://localhost:3000/api/LargeCollection?%24count=true&%24skiptoken=50')
          count = response['@odata.count']
          expect(count).to eq(102)
        end

        it do
          json_string = schema.execute('LargeCollection',
                                       context: Context.new,
                                       query_options: { '$skiptoken' => '50' })
          response = Oj.load(json_string)
          context = response['@odata.context']
          expect(context).to eq('http://localhost:3000/api/$metadata#LargeCollection')
          expect(response['value'].count).to eq(2)
          next_link = response['@odata.nextLink']
          expect(next_link).to eq('http://localhost:3000/api/LargeCollection?%24skiptoken=50&%24skiptoken=100')
        end

        it do
          json_string = schema.execute('LargeCollection',
                                       context: Context.new,
                                       query_options: { '$skiptoken' => '100' })
          response = Oj.load(json_string)
          context = response['@odata.context']
          expect(context).to eq('http://localhost:3000/api/$metadata#LargeCollection')
          expect(response['value'].count).to eq(2)
          next_link = response['@odata.nextLink']
          expect(next_link).to be_nil
        end
      end

      it do
        json_string = schema.execute('LargeCollection',
                                     context: Context.new,
                                     query_options: { '$filter' => "id ne '1'",
                                                      '$top' => '100' })
        response = Oj.load(json_string)
        context = response['@odata.context']
        expect(context).to eq('http://localhost:3000/api/$metadata#LargeCollection')
        expect(response['value'].count).to eq(50)
        next_link = response['@odata.nextLink']
        expect(next_link).to eq(
          'http://localhost:3000/api/LargeCollection?%24filter=id+ne+%271%27&%24top=100&%24skiptoken=50'
        )
      end
    end
  end
end
