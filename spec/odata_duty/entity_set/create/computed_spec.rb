require 'spec_helper'

class CreateComputedTestEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'name', String
  property 'created_at', DateTime, computed: true
end

class CreateComputedTestSet < OdataDuty::EntitySet
  entity_type CreateComputedTestEntity

  def create(params)
    raise 'created_at must be nil' unless params.created_at.nil?

    params
  end
end

class CreateComputedKeyTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String

  def id
    object.id
  end
end

class CreateComputedKeyTestSet < OdataDuty::EntitySet
  entity_type CreateComputedKeyTestEntity

  ServerAssigned = Struct.new(:id, :name)

  def create(params)
    raise 'id must be nil' unless params.id.nil?

    ServerAssigned.new('server-assigned', params.name)
  end
end

class CreateComputedTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CreateComputedTestSet, CreateComputedKeyTestSet]
end

RSpec.describe OdataDuty::EntitySet, 'computed properties on create' do
  subject(:schema) { CreateComputedTestSchema }

  def create(set, query_options)
    Oj.load(schema.create(set, context: Context.new, query_options: query_options))
  end

  describe 'computed non-key property' do
    it 'is silently ignored and reads back as nil while siblings coerce normally' do
      response = create('CreateComputedTest',
                        'id' => '1', 'name' => 'foo', 'created_at' => '2021-01-01T00:00:00Z')
      expect(response).to include('name' => 'foo', 'created_at' => nil)
    end

    it 'drops a wrong-typed computed value without raising InvalidType' do
      expect do
        create('CreateComputedTest', 'id' => '1', 'name' => 'foo', 'created_at' => 12_345)
      end.not_to raise_error
    end
  end

  describe 'property_ref defaulting to computed: true' do
    it 'makes the key read-only so a supplied id is ignored and server-assigned' do
      response = create('CreateComputedKeyTest', 'id' => '99', 'name' => 'bar')
      expect(response).to include('id' => 'server-assigned', 'name' => 'bar')
    end
  end
end
