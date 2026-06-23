require 'spec_helper'

class ComputedOas2BuilderCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(params)
    params
  end
end

RSpec.describe OdataDuty::SchemaBuilder, 'computed properties as readOnly in $oas2' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'ComputedOas2BuilderEntity') do |et|
        et.property_ref 'id', String
        et.property 'user_name', String, nullable: false
        et.property 'created_at', DateTime, computed: true
      end

      s.add_entity_set(name: 'ComputedOas2BuilderCollection', entity_type: entity,
                       resolver: 'ComputedOas2BuilderCollectionResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(oas2_schema, context: Context.new) }
  let(:properties) { json.dig('definitions', 'ComputedOas2BuilderEntity', 'properties') }

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

  it 'keeps the post body referencing the shared entity definition' do
    body = json.dig('paths', '/ComputedOas2BuilderCollection', 'post', 'parameters').first
    expect(body['schema']).to eq('$ref' => '#/definitions/ComputedOas2BuilderEntity')
  end
end
