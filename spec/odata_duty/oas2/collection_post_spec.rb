require 'spec_helper'

class PostPinWidgetResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

class PostPinGadgetResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class PostPinNullableResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

RSpec.describe OdataDuty::OAS2, 'collection POST operation contract' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      widget = s.add_entity_type(name: 'PostPinWidget') do |et|
        et.property_ref 'id', String
        et.property 'account_number', String, nullable: false, mutability: :immutable
        et.property 'name', String, nullable: false
        et.property 'note', String
        et.property 'updated_via', String, mutability: :non_insertable
        et.property 'created_at', DateTime, mutability: :computed
      end
      s.add_entity_set(name: 'PostPinWidgets', entity_type: widget,
                       resolver: 'PostPinWidgetResolver')

      nullable = s.add_entity_type(name: 'PostPinNullable') do |et|
        et.property_ref 'id', String
        et.property 'note', String
        et.property 'label', String
      end
      s.add_entity_set(name: 'PostPinNullables', entity_type: nullable,
                       resolver: 'PostPinNullableResolver')

      gadget = s.add_entity_type(name: 'PostPinGadget') do |et|
        et.property_ref 'code', String
        et.property 'title', String, nullable: false
      end
      s.add_entity_set(name: 'PostPinGadgets', entity_type: gadget,
                       resolver: 'PostPinGadgetResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  describe 'the post operation for a creatable set' do
    let(:post) { json.dig('paths', '/PostPinWidgets', 'post') }

    it 'pins the entire operation: operationId, produces, parameters, and responses' do
      expect(post).to eq(
        'operationId' => 'CreatePostPinWidgets',
        'produces' => ['application/json'],
        'parameters' => [
          { 'name' => 'body', 'in' => 'body', 'required' => true,
            'schema' => { '$ref' => '#/definitions/PostPinWidgetCreate' } }
        ],
        'responses' => {
          '200' => { 'description' => 'Success',
                     'schema' => { '$ref' => '#/definitions/PostPinWidget' } },
          '201' => { 'description' => 'Created',
                     'schema' => { '$ref' => '#/definitions/PostPinWidget' } },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      )
    end
  end

  describe 'the <Entity>Create request body definition' do
    let(:definition) { json.dig('definitions', 'PostPinWidgetCreate') }

    it 'declares the object type' do
      expect(definition['type']).to eq('object')
    end

    it 'exposes exactly the create-settable properties' do
      expect(definition['properties'].keys).to eq(%w[account_number name note])
    end

    it 'requires exactly the non-nullable create-settable properties' do
      expect(definition['required']).to eq(%w[account_number name])
    end
  end

  describe 'the <Entity>Create definition when every settable property is nullable' do
    let(:definition) { json.dig('definitions', 'PostPinNullableCreate') }

    it 'still exposes the nullable create-settable properties' do
      expect(definition['properties'].keys).to eq(%w[note label])
    end

    it 'omits the required key entirely' do
      expect(definition).not_to have_key('required')
    end
  end

  describe 'a read-only set' do
    it 'has no post operation' do
      expect(json.dig('paths', '/PostPinGadgets')).not_to have_key('post')
    end

    it 'emits no <Entity>Create definition' do
      expect(json['definitions']).not_to have_key('PostPinGadgetCreate')
    end
  end
end
