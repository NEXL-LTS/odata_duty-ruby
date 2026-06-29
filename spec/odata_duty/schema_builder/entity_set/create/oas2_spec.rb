require 'spec_helper'

class CreatableBuilderCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

class ReadOnlyBuilderCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'gates $oas2 post on create support' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'CreateOas2BuilderTestEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end

      s.add_entity_set(name: 'CreatableBuilderCollection', entity_type: entity,
                       resolver: 'CreatableBuilderCollectionResolver')
      s.add_entity_set(name: 'ReadOnlyBuilderCollection', entity_type: entity,
                       resolver: 'ReadOnlyBuilderCollectionResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe '/CreatableBuilderCollection' do
    let(:path) { json['paths']['/CreatableBuilderCollection'] }

    it 'includes a post operation when create is supported' do
      expect(path).to have_key('post')
    end

    it 'uses a Create operationId for the post operation' do
      expect(path['post']['operationId']).to start_with('Create')
    end
  end

  describe '/ReadOnlyBuilderCollection' do
    let(:path) { json['paths']['/ReadOnlyBuilderCollection'] }

    it 'includes a get operation' do
      expect(path).to have_key('get')
    end

    it 'does not include a post operation when create is not supported' do
      expect(path).not_to have_key('post')
    end
  end
end

class MutabilityCreateOas2BuilderResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

class WritableCreateOas2BuilderResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'emits a <Entity>Create request body definition' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      mutability_entity = s.add_entity_type(name: 'MutabilityCreateOas2BuilderEntity') do |et|
        et.property_ref 'id', String
        et.property 'account_number', String, nullable: false, mutability: :immutable
        et.property 'note', String
        et.property 'updated_via', String, mutability: :non_insertable
        et.property 'created_at', DateTime, mutability: :computed
      end
      s.add_entity_set(name: 'MutabilityCreateOas2BuilderCollection',
                       entity_type: mutability_entity,
                       resolver: 'MutabilityCreateOas2BuilderResolver')

      writable_entity = s.add_entity_type(name: 'WritableCreateOas2BuilderEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
        et.property 'note', String
      end
      s.add_entity_set(name: 'WritableCreateOas2BuilderCollection',
                       entity_type: writable_entity,
                       resolver: 'WritableCreateOas2BuilderResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe 'MutabilityCreateOas2BuilderEntityCreate definition' do
    let(:definition) { json.dig('definitions', 'MutabilityCreateOas2BuilderEntityCreate') }

    it 'declares the object type' do
      expect(definition['type']).to eq('object')
    end

    it 'includes read_write and immutable properties' do
      expect(definition['properties']).to include('account_number', 'note')
    end

    it 'omits computed and non_insertable properties' do
      expect(definition['properties']).not_to include('created_at', 'updated_via', 'id')
    end

    it 'requires the non-nullable create-settable properties' do
      expect(definition['required']).to eq(['account_number'])
    end

    it 'does not emit x-ms-mutability' do
      expect(definition.to_s).not_to include('x-ms-mutability')
    end
  end

  describe 'MutabilityCreateOas2BuilderCollection post operation' do
    let(:post) { json.dig('paths', '/MutabilityCreateOas2BuilderCollection', 'post') }

    it 'references the <Entity>Create definition in the body parameter' do
      body = post['parameters'].first
      expect(body['schema'])
        .to eq('$ref' => '#/definitions/MutabilityCreateOas2BuilderEntityCreate')
    end

    it 'still responds with the full entity definition on 200' do
      expect(post.dig('responses', '200', 'schema'))
        .to eq('$ref' => '#/definitions/MutabilityCreateOas2BuilderEntity')
    end

    it 'still responds with the full entity definition on 201' do
      expect(post.dig('responses', '201', 'schema'))
        .to eq('$ref' => '#/definitions/MutabilityCreateOas2BuilderEntity')
    end
  end

  describe 'a create-able set with no constrained properties' do
    let(:definition) { json.dig('definitions', 'WritableCreateOas2BuilderEntityCreate') }

    it 'still emits a <Entity>Create definition' do
      expect(definition).not_to be_nil
    end

    it 'includes all writable properties' do
      expect(definition['properties']).to include('name', 'note')
    end

    it 'requires only the non-nullable writable properties' do
      expect(definition['required']).to eq(['name'])
    end
  end
end
