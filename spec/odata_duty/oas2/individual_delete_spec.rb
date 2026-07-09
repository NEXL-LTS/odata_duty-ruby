require 'spec_helper'

class IndivDeleteIntResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end

  def delete(id)
    id
  end
end

class IndivDeleteStrResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end

  def delete(id)
    id
  end
end

class IndivDeleteReadOnlyResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end
end

RSpec.describe OdataDuty::OAS2, 'individual DELETE operation contract' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      int_entity = s.add_entity_type(name: 'IndivDeleteIntWidget') do |et|
        et.property_ref 'id', Integer
        et.property 'name', String, nullable: false
      end
      str_entity = s.add_entity_type(name: 'IndivDeleteStrWidget') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
      end

      s.add_entity_set(name: 'IndivDeleteIntWidgets', entity_type: int_entity,
                       resolver: 'IndivDeleteIntResolver')
      s.add_entity_set(name: 'IndivDeleteStrWidgets', entity_type: str_entity,
                       resolver: 'IndivDeleteStrResolver')
      s.add_entity_set(name: 'IndivDeleteReadOnlys', entity_type: str_entity,
                       resolver: 'IndivDeleteReadOnlyResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  describe 'the delete operation for an integer-keyed set' do
    let(:delete) { json.dig('paths', '/IndivDeleteIntWidgets({id})', 'delete') }

    it 'pins the entire operation with an integer id path parameter' do
      expect(delete).to eq(
        'operationId' => 'DeleteIndivDeleteIntWidgets',
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'integer' }
        ],
        'responses' => {
          '204' => { 'description' => 'No Content' },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end

    it 'emits no produces key for the delete operation' do
      expect(delete).not_to have_key('produces')
    end

    it 'emits no schema key on the 204 response' do
      expect(delete.dig('responses', '204')).not_to have_key('schema')
    end
  end

  describe 'the delete operation for a string-keyed set' do
    let(:delete) { json.dig('paths', '/IndivDeleteStrWidgets({id})', 'delete') }

    it 'pins the entire operation with a string id path parameter' do
      expect(delete).to eq(
        'operationId' => 'DeleteIndivDeleteStrWidgets',
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' }
        ],
        'responses' => {
          '204' => { 'description' => 'No Content' },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end

  describe 'a read-only set without a delete method' do
    let(:path) { json.dig('paths', '/IndivDeleteReadOnlys({id})') }

    it 'exposes no delete operation' do
      expect(path).not_to have_key('delete')
    end
  end
end
