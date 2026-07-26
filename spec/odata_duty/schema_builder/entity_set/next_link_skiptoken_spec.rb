require 'spec_helper'

class ArrayTokenPagingResolver < OdataDuty::SetResolver
  RECORDS = (1..2).map { |i| OpenStruct.new(id: i.to_s) }

  def od_after_init
    @records = RECORDS
  end

  def collection
    od_next_link_skiptoken([10, 20])
    @records
  end
end

class FinalPagePagingResolver < OdataDuty::SetResolver
  RECORDS = (1..2).map { |i| OpenStruct.new(id: i.to_s) }

  def od_after_init
    @records = RECORDS
  end

  def collection
    @records
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'server-driven paging skiptoken' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        entity = s.add_entity_type(name: 'PagedToken') do |et|
          et.property_ref 'id', String
        end

        s.add_entity_set(name: 'ArrayTokenPaging', entity_type: entity,
                         resolver: 'ArrayTokenPagingResolver')
        s.add_entity_set(name: 'FinalPagePaging', entity_type: entity,
                         resolver: 'FinalPagePagingResolver')
      end
    end

    def response_for(path)
      Oj.load(schema.execute(path, context: Context.new))
    end

    it 'stringifies the skiptoken so a non-string token is a single encoded value' do
      next_link = response_for('ArrayTokenPaging')['@odata.nextLink']
      expect(next_link).to eq('https://localhost/ArrayTokenPaging?%24skiptoken=%5B10%2C+20%5D')
    end

    it 'omits @odata.nextLink when no skiptoken is set' do
      expect(response_for('FinalPagePaging')).not_to have_key('@odata.nextLink')
    end
  end
end
