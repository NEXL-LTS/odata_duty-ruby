require 'spec_helper'

class SupportsCollectionResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1')]
  end
end

class LargeCollectionResolver < OdataDuty::SetResolver
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

class DoesNotSupportCollectionResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can specific individual result' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        collection_entity = s.add_entity_type(name: 'CollectionTest') do |et|
          et.property_ref 'id', String
        end

        s.add_entity_set(name: 'SupportsCollection', entity_type: collection_entity,
                         resolver: 'SupportsCollectionResolver')
        s.add_entity_set(name: 'DoesNotSupportCollection', entity_type: collection_entity,
                         resolver: 'DoesNotSupportCollectionResolver')
        s.add_entity_set(name: 'LargeCollection', entity_type: collection_entity,
                         resolver: 'LargeCollectionResolver')
      end
    end

    describe '#execute' do
      describe 'collection' do
        it do
          json_string = schema.execute('SupportsCollection', context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            {
              '@odata.context' => '$metadata#SupportsCollection',
              'value' => [
                '@odata.id' => 'SupportsCollection(\'1\')',
                'id' => '1'
              ]
            }
          )
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
          expect(context).to eq('$metadata#LargeCollection')
          expect(response['value'].count).to eq(50)
          next_link = response['@odata.nextLink']
          expect(next_link).to eq('LargeCollection?$skiptoken=50')
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
            expect(context).to eq('$metadata#LargeCollection')
            expect(response['value'].count).to eq(50)
            next_link = response['@odata.nextLink']
            expect(next_link).to eq('LargeCollection?$count=true&$skiptoken=50')
            count = response['@odata.count']
            expect(count).to eq(102)
          end

          it do
            json_string = schema.execute('LargeCollection',
                                         context: Context.new,
                                         query_options: { '$skiptoken' => '50' })
            response = Oj.load(json_string)
            context = response['@odata.context']
            expect(context).to eq('$metadata#LargeCollection')
            expect(response['value'].count).to eq(2)
            next_link = response['@odata.nextLink']
            expect(next_link).to eq('LargeCollection?$skiptoken=100')
          end

          it do
            json_string = schema.execute('LargeCollection',
                                         context: Context.new,
                                         query_options: { '$skiptoken' => '100' })
            response = Oj.load(json_string)
            context = response['@odata.context']
            expect(context).to eq('$metadata#LargeCollection')
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
          expect(context).to eq('$metadata#LargeCollection')
          expect(response['value'].count).to eq(50)
          next_link = response['@odata.nextLink']
          expect(next_link).to eq("LargeCollection?$filter=id ne '1'&$top=100&$skiptoken=50")
        end
      end
    end
  end
end
