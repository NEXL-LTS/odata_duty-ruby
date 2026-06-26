require 'spec_helper'

class DeletableBuilderOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end

  def delete(id)
    id
  end
end

class ReadOnlyBuilderDeleteOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end
end

class IntegerKeyBuilderDeleteOas2Resolver < OdataDuty::SetResolver
  def individual(id)
    { 'id' => id, 'name' => 'x' }
  end

  def delete(id)
    id
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'gates $oas2 delete on delete support' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'DeleteOas2BuilderTestEntity') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end

      int_entity = s.add_entity_type(name: 'IntDeleteOas2BuilderTestEntity') do |et|
        et.property_ref 'id', Integer
        et.property 'name', String
      end

      s.add_entity_set(name: 'DeletableBuilderOas2', entity_type: entity,
                       resolver: 'DeletableBuilderOas2Resolver')
      s.add_entity_set(name: 'ReadOnlyBuilderDeleteOas2', entity_type: entity,
                       resolver: 'ReadOnlyBuilderDeleteOas2Resolver')
      s.add_entity_set(name: 'IntegerKeyBuilderDeleteOas2', entity_type: int_entity,
                       resolver: 'IntegerKeyBuilderDeleteOas2Resolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }

  describe '/DeletableBuilderOas2({id})' do
    let(:path) { json['paths']['/DeletableBuilderOas2({id})'] }

    it 'includes a delete operation when delete is supported' do
      expect(path).to have_key('delete')
    end

    it 'uses a Delete operationId for the delete operation' do
      expect(path['delete']['operationId']).to eq('DeleteDeletableBuilderOas2')
    end

    it 'requires only an id path parameter and no body' do
      expect(path['delete']['parameters']).to eq(
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' }
        ]
      )
    end

    it 'exposes 204 and default responses with no success schema' do
      expect(path['delete']['responses']).to eq(
        '204' => { 'description' => 'No Content' },
        'default' => { 'description' => 'Unexpected error',
                       'schema' => { '$ref' => '#/definitions/Error' } }
      )
    end
  end

  describe '/IntegerKeyBuilderDeleteOas2({id})' do
    let(:path) { json['paths']['/IntegerKeyBuilderDeleteOas2({id})'] }

    it 'uses an integer id path parameter for an integer-keyed set' do
      expect(path['delete']['parameters']).to eq(
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'integer' }
        ]
      )
    end
  end

  describe '/ReadOnlyBuilderDeleteOas2({id})' do
    let(:path) { json['paths']['/ReadOnlyBuilderDeleteOas2({id})'] }

    it 'includes a get operation' do
      expect(path).to have_key('get')
    end

    it 'does not include a delete operation when delete is not supported' do
      expect(path).not_to have_key('delete')
    end
  end
end
