require 'spec_helper'

class ProfilesReuseResolver < OdataDuty::SetResolver
  def collection
    [
      OpenStruct.new(id: '1', name: 'ann', badge: OpenStruct.new(slug: 'a')),
      OpenStruct.new(id: '2', name: 'bob', badge: OpenStruct.new(slug: 'b')),
      OpenStruct.new(id: '3', name: 'cid', badge: nil)
    ]
  end

  def individual(id)
    collection.find { |r| r.id == id }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'computed properties across rows reuse one mapper' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        badge = s.add_complex_type(name: 'Badge') do |ct|
          ct.property 'label', String, method: ->(b) { "badge-#{b.slug}" }
        end

        profile = s.add_entity_type(name: 'Profile') do |et|
          et.property_ref 'id', String
          et.property 'greeting', String, method: ->(p) { "hello-#{p.name}" }
          et.property 'badge', badge, nullable: true
        end

        s.add_entity_set(name: 'Profiles', entity_type: profile,
                         resolver: 'ProfilesReuseResolver')
      end
    end

    it 'recomputes an entity-level computed property per row from that row object' do
      response = Oj.load(schema.execute('Profiles', context: Context.new))
      expect(response['value'].map { |r| r['greeting'] })
        .to eq(%w[hello-ann hello-bob hello-cid])
    end

    it 'recomputes a nested complex computed property per row from that nested object' do
      response = Oj.load(schema.execute('Profiles', context: Context.new))
      expect(response['value'].map { |r| r['badge'] })
        .to eq([{ 'label' => 'badge-a' }, { 'label' => 'badge-b' }, nil])
    end

    it 'computes the entity-level property from the addressed row on an individual read' do
      response = Oj.load(schema.execute("Profiles('2')", context: Context.new))
      expect(response['greeting']).to eq('hello-bob')
    end
  end
end
