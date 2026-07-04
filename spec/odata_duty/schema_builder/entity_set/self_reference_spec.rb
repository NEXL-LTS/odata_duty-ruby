require 'spec_helper'

class BossChainResolver < OdataDuty::SetResolver
  def od_after_init
    alice = OpenStruct.new(id: 1, boss: nil)
    @records = [alice, OpenStruct.new(id: 2, boss: alice)]
  end

  def collection
    @records
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'self-referencing entity types' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'HR', host: 'localhost') do |s|
        manager = s.add_entity_type(name: 'Manager') do |et|
          et.property_ref 'id', Integer
          et.property 'boss', et, nullable: true
        end
        s.add_entity_set(name: 'Managers', entity_type: manager, resolver: 'BossChainResolver')
      end
    end

    it 'declares the self-reference once in $metadata' do
      xml = schema.metadata_xml
      expect(xml).to include('<Property Name="boss" Nullable="true" Type="HR.Manager" />')
      expect(xml.scan('<EntityType Name="Manager">').size).to eq(1)
    end

    it 'returns self-referenced values nested in payloads, ending where the data ends' do
      json = schema.execute('Managers', context: Context.new, query_options: {})
      bosses = Oj.load(json).fetch('value').map { |manager| manager['boss'] }
      expect(bosses).to eq([nil, { 'id' => 1, 'boss' => nil }])
    end
  end
end
