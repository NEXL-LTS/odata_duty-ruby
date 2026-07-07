require 'spec_helper'

class WriteContextEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'name', String
  property 'created_via', String

  property 'profile_url', String
  def profile_url
    od_context.od_full_url("Profiles(#{object.id})")
  end
end

class WriteContextSet < OdataDuty::EntitySet
  entity_type WriteContextEntity

  def create(input)
    OpenStruct.new(id: input.id, name: input.name,
                   created_via: context.od_full_url("audit/#{input.id}"))
  end

  def update(id, input)
    return nil unless id == 'known'

    OpenStruct.new(id: id, name: input.name,
                   created_via: context.od_full_url("audit/#{id}"))
  end

  def delete(id)
    return nil unless context.od_full_url("audit/#{id}").end_with?("audit/#{id}")

    true
  end
end

class WriteContextSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [WriteContextSet]
end

RSpec.describe OdataDuty::EntitySet, 'threads request context into write hooks and response' do
  subject(:schema) { WriteContextSchema }

  describe '#create' do
    let(:response) do
      json = schema.create('WriteContext', context: Context.new,
                                           query_options: { 'id' => '7', 'name' => 'Ada' })
      Oj.load(json)
    end

    it 'exposes the live context to the create hook and reflects it in the record' do
      expect(response).to include('created_via' => 'http://localhost:3000/api/audit/7')
    end

    it 'threads the request context into obj_to_hash so a context-reading property renders' do
      expect(response).to include('profile_url' => 'http://localhost:3000/api/Profiles(7)')
    end

    it 'coerces the body under the :create operation' do
      expect(response).to include('id' => '7', 'name' => 'Ada')
    end
  end

  describe '#update' do
    let(:response) do
      json = schema.update("WriteContext('known')", context: Context.new,
                                                    query_options: { 'name' => 'Grace' })
      Oj.load(json)
    end

    it 'exposes the live context to the update hook and reflects it in the record' do
      expect(response).to include('created_via' => 'http://localhost:3000/api/audit/known')
    end

    it 'threads the request context into obj_to_hash so a context-reading property renders' do
      expect(response).to include('profile_url' => 'http://localhost:3000/api/Profiles(known)')
    end

    it 'coerces the body under the :update operation' do
      expect(response).to include('id' => 'known', 'name' => 'Grace')
    end
  end

  describe '#delete' do
    it 'exposes the live context to the delete hook' do
      expect do
        schema.delete("WriteContext('anything')", context: Context.new, query_options: {})
      end.not_to raise_error
    end
  end
end
