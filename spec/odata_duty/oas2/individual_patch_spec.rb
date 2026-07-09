require 'spec_helper'

class PatchPinIntResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end

  def update(id, params)
    [id, params]
  end
end

class PatchPinStrResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end

  def update(id, params)
    [id, params]
  end
end

class PatchPinNonNullableResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end

  def update(id, params)
    [id, params]
  end
end

class PatchPinReadOnlyResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end
end

RSpec.describe OdataDuty::OAS2, 'individual PATCH operation contract' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      int_entity = s.add_entity_type(name: 'PatchPinIntWidget') do |et|
        et.property_ref 'id', Integer
        et.property 'account_number', String, nullable: false, mutability: :immutable
        et.property 'name', String, nullable: false
        et.property 'note', String
        et.property 'updated_via', String, mutability: :non_insertable
        et.property 'created_at', DateTime, mutability: :computed
      end
      s.add_entity_set(name: 'PatchPinIntWidgets', entity_type: int_entity,
                       resolver: 'PatchPinIntResolver')

      str_entity = s.add_entity_type(name: 'PatchPinStrWidget') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end
      s.add_entity_set(name: 'PatchPinStrWidgets', entity_type: str_entity,
                       resolver: 'PatchPinStrResolver')

      non_nullable = s.add_entity_type(name: 'PatchPinNonNullableWidget') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
        et.property 'note', String, nullable: false
      end
      s.add_entity_set(name: 'PatchPinNonNullableWidgets', entity_type: non_nullable,
                       resolver: 'PatchPinNonNullableResolver')

      read_only = s.add_entity_type(name: 'PatchPinReadOnlyWidget') do |et|
        et.property_ref 'id', String
        et.property 'name', String
      end
      s.add_entity_set(name: 'PatchPinReadOnlyWidgets', entity_type: read_only,
                       resolver: 'PatchPinReadOnlyResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  describe 'the patch operation for an integer-keyed set' do
    let(:patch) { json.dig('paths', '/PatchPinIntWidgets({id})', 'patch') }

    it 'pins the entire operation with an integer id path parameter first' do
      expect(patch).to eq(
        'operationId' => 'UpdatePatchPinIntWidgets',
        'produces' => ['application/json'],
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'integer' },
          { 'name' => 'body', 'in' => 'body', 'required' => true,
            'schema' => { '$ref' => '#/definitions/PatchPinIntWidgetUpdate' } }
        ],
        'responses' => {
          '200' => { 'description' => 'Success',
                     'schema' => { '$ref' => '#/definitions/PatchPinIntWidget' } },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end

  describe 'the patch operation for a string-keyed set' do
    let(:patch) { json.dig('paths', '/PatchPinStrWidgets({id})', 'patch') }

    it 'pins the entire operation with a string id path parameter first' do
      expect(patch).to eq(
        'operationId' => 'UpdatePatchPinStrWidgets',
        'produces' => ['application/json'],
        'parameters' => [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => 'string' },
          { 'name' => 'body', 'in' => 'body', 'required' => true,
            'schema' => { '$ref' => '#/definitions/PatchPinStrWidgetUpdate' } }
        ],
        'responses' => {
          '200' => { 'description' => 'Success',
                     'schema' => { '$ref' => '#/definitions/PatchPinStrWidget' } },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end

  describe 'the <Entity>Update request body definition' do
    let(:definition) { json.dig('definitions', 'PatchPinIntWidgetUpdate') }

    it 'declares the object type' do
      expect(definition['type']).to eq('object')
    end

    it 'exposes exactly the update-settable properties, excluding key/immutable/computed' do
      expect(definition['properties'].keys).to eq(%w[name note updated_via])
    end

    it 'omits the required key entirely (PATCH is partial-merge)' do
      expect(definition).not_to have_key('required')
    end
  end

  describe 'the <Entity>Update definition when every settable property is non-nullable' do
    let(:definition) { json.dig('definitions', 'PatchPinNonNullableWidgetUpdate') }

    it 'still exposes the non-nullable update-settable properties' do
      expect(definition['properties'].keys).to eq(%w[name note])
    end

    it 'omits the required key entirely' do
      expect(definition).not_to have_key('required')
    end
  end

  describe 'a read-only set without an update method' do
    it 'has no patch operation' do
      expect(json.dig('paths', '/PatchPinReadOnlyWidgets({id})')).not_to have_key('patch')
    end

    it 'emits no <Entity>Update definition' do
      expect(json['definitions']).not_to have_key('PatchPinReadOnlyWidgetUpdate')
    end
  end
end
