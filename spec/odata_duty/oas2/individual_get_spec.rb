require 'spec_helper'

class IndivGetIntResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def individual(id)
    id
  end
end

class IndivGetStrResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def individual(id)
    id
  end
end

RSpec.describe OdataDuty::OAS2, 'individual GET operation contract' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      int_entity = s.add_entity_type(name: 'IndivGetIntWidget') do |et|
        et.property_ref 'id', Integer
        et.property 'name', String, nullable: false
      end
      str_entity = s.add_entity_type(name: 'IndivGetStrWidget') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
      end

      s.add_entity_set(name: 'IndivGetIntWidgets', entity_type: int_entity,
                       resolver: 'IndivGetIntResolver')
      s.add_entity_set(name: 'IndivGetStrWidgets', entity_type: str_entity,
                       resolver: 'IndivGetStrResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  describe 'the get operation for an integer-keyed set' do
    let(:get) { json.dig('paths', '/IndivGetIntWidgets({id})', 'get') }

    it 'pins the entire operation with an integer id path parameter' do
      expect(get).to eq(
        'operationId' => 'GetIndividualIndivGetIntWidgetsById',
        'produces' => ['application/json'],
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'integer' }
        ],
        'responses' => {
          '200' => { 'description' => 'Individual Response',
                     'schema' => { '$ref' => '#/definitions/IndivGetIntWidget' } },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end

  describe 'the get operation for a string-keyed set' do
    let(:get) { json.dig('paths', '/IndivGetStrWidgets({id})', 'get') }

    it 'pins the entire operation with a string id path parameter' do
      expect(get).to eq(
        'operationId' => 'GetIndividualIndivGetStrWidgetsById',
        'produces' => ['application/json'],
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' }
        ],
        'responses' => {
          '200' => { 'description' => 'Individual Response',
                     'schema' => { '$ref' => '#/definitions/IndivGetStrWidget' } },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end
end
