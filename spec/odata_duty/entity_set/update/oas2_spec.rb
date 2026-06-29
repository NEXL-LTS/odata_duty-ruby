require 'spec_helper'

class UpdatableOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end

  def update(id, params)
    [id, params]
  end
end

class ReadOnlyUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end
end

RSpec.describe OdataDuty::EntitySet, 'gates $oas2 patch on update support' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'UpdateOas2TestEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end

      s.add_entity_set(name: 'UpdatableOas2', entity_type: entity,
                       resolver: 'UpdatableOas2Resolver')
      s.add_entity_set(name: 'ReadOnlyUpdateOas2', entity_type: entity,
                       resolver: 'ReadOnlyUpdateOas2Resolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe '/UpdatableOas2({id})' do
    let(:path) { json['paths']['/UpdatableOas2({id})'] }

    it 'includes a patch operation when update is supported' do
      expect(path).to have_key('patch')
    end

    it 'uses an Update operationId for the patch operation' do
      expect(path['patch']['operationId']).to eq('UpdateUpdatableOas2')
    end

    it 'requires an id path parameter and a body parameter' do
      expect(path['patch']['parameters']).to eq(
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' },
          { 'name' => 'body', 'in' => 'body', 'required' => true,
            'schema' => { '$ref' => '#/definitions/UpdateOas2TestEntityUpdate' } }
        ]
      )
    end

    it 'exposes 200 and default responses' do
      expect(path['patch']['responses']).to eq(
        '200' => { 'description' => 'Success',
                   'schema' => { '$ref' => '#/definitions/UpdateOas2TestEntity' } },
        'default' => { 'description' => 'Unexpected error',
                       'schema' => { '$ref' => '#/definitions/Error' } }
      )
    end
  end

  describe '/ReadOnlyUpdateOas2({id})' do
    let(:path) { json['paths']['/ReadOnlyUpdateOas2({id})'] }

    it 'includes a get operation' do
      expect(path).to have_key('get')
    end

    it 'does not include a patch operation when update is not supported' do
      expect(path).not_to have_key('patch')
    end
  end
end

class MutabilityUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id }
  end

  def update(id, params)
    [id, params]
  end
end

class WritableUpdateOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id }
  end

  def update(id, params)
    [id, params]
  end
end

RSpec.describe OdataDuty::EntitySet, 'emits a <Entity>Update request body definition' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      mutability_entity = s.add_entity_type(name: 'MutabilityUpdateOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'account_number', String, nullable: false, mutability: :immutable
        et.property 'note', String
        et.property 'updated_via', String, mutability: :non_insertable
        et.property 'created_at', DateTime, mutability: :computed
      end
      s.add_entity_set(name: 'MutabilityUpdateOas2Collection', entity_type: mutability_entity,
                       resolver: 'MutabilityUpdateOas2Resolver')

      writable_entity = s.add_entity_type(name: 'WritableUpdateOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
        et.property 'note', String
      end
      s.add_entity_set(name: 'WritableUpdateOas2Collection', entity_type: writable_entity,
                       resolver: 'WritableUpdateOas2Resolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe 'MutabilityUpdateOas2EntityUpdate definition' do
    let(:definition) { json.dig('definitions', 'MutabilityUpdateOas2EntityUpdate') }

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

  describe 'MutabilityUpdateOas2Collection patch operation' do
    let(:patch) { json.dig('paths', '/MutabilityUpdateOas2Collection({id})', 'patch') }

    it 'references the <Entity>Update definition in the body parameter' do
      body = patch['parameters'].last
      expect(body['schema']).to eq('$ref' => '#/definitions/MutabilityUpdateOas2EntityUpdate')
    end

    it 'still responds with the full entity definition on 200' do
      expect(patch.dig('responses', '200', 'schema'))
        .to eq('$ref' => '#/definitions/MutabilityUpdateOas2Entity')
    end
  end

  describe 'an update-able set with no constrained properties' do
    let(:definition) { json.dig('definitions', 'WritableUpdateOas2EntityUpdate') }

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
