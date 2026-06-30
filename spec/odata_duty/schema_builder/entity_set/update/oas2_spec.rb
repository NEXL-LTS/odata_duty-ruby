require 'spec_helper'

class UpdatableBuilderOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end

  def update(id, params)
    [id, params]
  end
end

class ReadOnlyBuilderUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'gates $oas2 patch on update support' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'UpdateOas2BuilderTestEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end

      s.add_entity_set(name: 'UpdatableBuilderOas2', entity_type: entity,
                       resolver: 'UpdatableBuilderOas2Resolver')
      s.add_entity_set(name: 'ReadOnlyBuilderUpdateOas2', entity_type: entity,
                       resolver: 'ReadOnlyBuilderUpdateOas2Resolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe '/UpdatableBuilderOas2({id})' do
    let(:path) { json['paths']['/UpdatableBuilderOas2({id})'] }

    it 'includes a patch operation when update is supported' do
      expect(path).to have_key('patch')
    end

    it 'uses an Update operationId for the patch operation' do
      expect(path['patch']['operationId']).to eq('UpdateUpdatableBuilderOas2')
    end

    it 'requires an id path parameter and a body parameter' do
      expect(path['patch']['parameters']).to eq(
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' },
          { 'name' => 'body', 'in' => 'body', 'required' => true,
            'schema' => { '$ref' => '#/definitions/UpdateOas2BuilderTestEntityUpdate' } }
        ]
      )
    end

    it 'exposes 200 and default responses' do
      expect(path['patch']['responses']).to eq(
        '200' => { 'description' => 'Success',
                   'schema' => { '$ref' => '#/definitions/UpdateOas2BuilderTestEntity' } },
        'default' => { 'description' => 'Unexpected error',
                       'schema' => { '$ref' => '#/definitions/Error' } }
      )
    end
  end

  describe '/ReadOnlyBuilderUpdateOas2({id})' do
    let(:path) { json['paths']['/ReadOnlyBuilderUpdateOas2({id})'] }

    it 'includes a get operation' do
      expect(path).to have_key('get')
    end

    it 'does not include a patch operation when update is not supported' do
      expect(path).not_to have_key('patch')
    end
  end
end

class MutabilityBuilderUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id }
  end

  def update(id, params)
    [id, params]
  end
end

class WritableBuilderUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id }
  end

  def update(id, params)
    [id, params]
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'emits a <Entity>Update request body definition' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      mutability_entity = s.add_entity_type(name: 'MutabilityBuilderUpdateOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'account_number', String, nullable: false, mutability: :immutable
        et.property 'note', String
        et.property 'updated_via', String, mutability: :non_insertable
        et.property 'created_at', DateTime, mutability: :computed
      end
      s.add_entity_set(name: 'MutabilityBuilderUpdateOas2Collection',
                       entity_type: mutability_entity,
                       resolver: 'MutabilityBuilderUpdateOas2Resolver')

      writable_entity = s.add_entity_type(name: 'WritableBuilderUpdateOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
        et.property 'note', String
      end
      s.add_entity_set(name: 'WritableBuilderUpdateOas2Collection',
                       entity_type: writable_entity,
                       resolver: 'WritableBuilderUpdateOas2Resolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe 'MutabilityBuilderUpdateOas2EntityUpdate definition' do
    let(:definition) { json.dig('definitions', 'MutabilityBuilderUpdateOas2EntityUpdate') }

    it 'declares the object type' do
      expect(definition['type']).to eq('object')
    end

    it 'includes read_write and non_insertable properties' do
      expect(definition['properties']).to include('note', 'updated_via')
    end

    it 'omits computed, immutable, and the key properties' do
      expect(definition['properties']).not_to include('created_at', 'account_number', 'id')
    end

    it 'does not emit a required key (PATCH is partial-merge)' do
      expect(definition).not_to have_key('required')
    end

    it 'does not emit x-ms-mutability' do
      expect(definition.to_s).not_to include('x-ms-mutability')
    end
  end

  describe 'MutabilityBuilderUpdateOas2Collection patch operation' do
    let(:patch) do
      json.dig('paths', '/MutabilityBuilderUpdateOas2Collection({id})', 'patch')
    end

    it 'references the <Entity>Update definition in the body parameter' do
      body = patch['parameters'].last
      expect(body['schema'])
        .to eq('$ref' => '#/definitions/MutabilityBuilderUpdateOas2EntityUpdate')
    end

    it 'still responds with the full entity definition on 200' do
      expect(patch.dig('responses', '200', 'schema'))
        .to eq('$ref' => '#/definitions/MutabilityBuilderUpdateOas2Entity')
    end
  end

  describe 'an update-able set with no constrained properties' do
    let(:definition) { json.dig('definitions', 'WritableBuilderUpdateOas2EntityUpdate') }

    it 'still emits a <Entity>Update definition' do
      expect(definition).not_to be_nil
    end

    it 'includes all update-settable properties' do
      expect(definition['properties']).to include('name', 'note')
    end

    it 'does not emit a required key' do
      expect(definition).not_to have_key('required')
    end
  end
end
