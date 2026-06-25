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
            'schema' => { '$ref' => '#/definitions/UpdateOas2BuilderTestEntity' } }
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
