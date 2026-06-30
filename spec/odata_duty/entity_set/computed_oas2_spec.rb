require 'spec_helper'

class ComputedOas2CollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

RSpec.describe OdataDuty::EntitySet, 'computed properties as readOnly in $oas2' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'ComputedOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'user_name', String, nullable: false
        et.property 'created_at', DateTime, computed: true
      end

      s.add_entity_set(name: 'ComputedOas2Collection', entity_type: entity,
                       resolver: 'ComputedOas2CollectionResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }
  let(:properties) { json.dig('definitions', 'ComputedOas2Entity', 'properties') }

  it 'marks the key property as readOnly by default (computed)' do
    expect(properties['id']).to eq('type' => 'string', 'readOnly' => true)
  end

  it 'does not mark a writable property as readOnly' do
    expect(properties['user_name']).to eq('type' => 'string')
  end

  it 'marks a computed nullable property with both readOnly and x-nullable' do
    expect(properties['created_at']).to eq(
      'type' => 'string', 'format' => 'date-time', 'readOnly' => true, 'x-nullable' => true
    )
  end

  it 'references the <Entity>Create definition in the post body' do
    body = json.dig('paths', '/ComputedOas2Collection', 'post', 'parameters').first
    expect(body['schema']).to eq('$ref' => '#/definitions/ComputedOas2EntityCreate')
  end

  it 'omits the computed and key properties from the <Entity>Create definition' do
    create_properties = json.dig('definitions', 'ComputedOas2EntityCreate', 'properties')
    expect(create_properties.keys).to contain_exactly('user_name')
  end
end
