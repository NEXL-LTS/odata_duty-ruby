require 'spec_helper'

class SelectMemoResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1', alpha: 'a', beta: 'b', gamma: 'g')]
  end

  def individual(id)
    collection.find { |r| r.id == id }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType,
                 '$select property ordering is normalized when memoized' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'SelectMemo') do |et|
          et.property_ref 'id', String
          et.property 'alpha', String
          et.property 'beta', String
          et.property 'gamma', String
        end

        s.add_entity_set(name: 'SelectMemo', entity_type: entity, resolver: 'SelectMemoResolver')
      end
    end

    def data_keys(select)
      json = schema.execute('SelectMemo', context: Context.new,
                                          query_options: { '$select' => select })
      Oj.load(json)['value'].first.keys - ['@odata.id']
    end

    it 'yields the same property key order regardless of the order names are requested in' do
      forward = data_keys('alpha,beta')
      reversed = data_keys('beta,alpha')
      expect(reversed).to eq(forward)
    end

    it 'shapes each distinct selection with exactly the requested property keys' do
      expect(data_keys('id,gamma')).to contain_exactly('id', 'gamma')
      expect(data_keys('id,alpha,beta,gamma')).to contain_exactly('id', 'alpha', 'beta', 'gamma')
    end
  end
end
