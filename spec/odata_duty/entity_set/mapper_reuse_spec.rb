require 'spec_helper'

class BadgeComplexType < OdataDuty::ComplexType
  property 'label', String

  def label
    "badge-#{object.slug}"
  end
end

class ProfileEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'greeting', String
  property 'badge', BadgeComplexType, nullable: true

  def greeting
    "hello-#{object.name}"
  end
end

class ProfilesSet < OdataDuty::EntitySet
  entity_type ProfileEntity

  def od_after_init
    @records = [
      OpenStruct.new(id: '1', name: 'ann', badge: OpenStruct.new(slug: 'a')),
      OpenStruct.new(id: '2', name: 'bob', badge: OpenStruct.new(slug: 'b')),
      OpenStruct.new(id: '3', name: 'cid', badge: nil)
    ]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end
end

class ProfilesSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ProfilesSet]
end

RSpec.describe OdataDuty::EntitySet, 'computed properties across rows reuse one mapper' do
  subject(:schema) { ProfilesSchema }

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
