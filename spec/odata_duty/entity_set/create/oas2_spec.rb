require 'spec_helper'

class CreatableCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

class ReadOnlyCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

RSpec.describe OdataDuty::EntitySet, 'gates $oas2 post on create support' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'CreateOas2TestEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end

      s.add_entity_set(name: 'CreatableCollection', entity_type: entity,
                       resolver: 'CreatableCollectionResolver')
      s.add_entity_set(name: 'ReadOnlyCollection', entity_type: entity,
                       resolver: 'ReadOnlyCollectionResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe '/CreatableCollection' do
    let(:path) { json['paths']['/CreatableCollection'] }

    it 'includes a post operation when create is supported' do
      expect(path).to have_key('post')
    end

    it 'uses a Create operationId for the post operation' do
      expect(path['post']['operationId']).to start_with('Create')
    end
  end

  describe '/ReadOnlyCollection' do
    let(:path) { json['paths']['/ReadOnlyCollection'] }

    it 'includes a get operation' do
      expect(path).to have_key('get')
    end

    it 'does not include a post operation when create is not supported' do
      expect(path).not_to have_key('post')
    end
  end
end
