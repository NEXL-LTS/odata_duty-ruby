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
            'schema' => { '$ref' => '#/definitions/UpdateOas2TestEntity' } }
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
