require 'spec_helper'

class SingleScalarTypesResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

RSpec.describe OdataDuty::OAS2, 'single (non-collection) scalar property type mapping' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      status = s.add_enum_type(name: 'SingleScalarStatus') do |e|
        e.member 'Active'
        e.member 'Inactive'
      end
      entity = s.add_entity_type(name: 'SingleScalarTypesEntity') do |et|
        et.property_ref 'id', String
        et.property 'count', Integer
        et.property 'label', String
        et.property 'born_on', Date
        et.property 'seen_at', DateTime
        et.property 'active', TrueClass
        et.property 'status', status
      end

      s.add_entity_set(name: 'SingleScalarTypes', entity_type: entity,
                       resolver: 'SingleScalarTypesResolver')
    end
  end

  let(:properties) do
    OdataDuty::OAS2.build_json(oas2_schema, context: Context.new)
                   .dig('definitions', 'SingleScalarTypesEntity', 'properties')
  end

  it 'maps an Integer property to integer / int64' do
    expect(properties['count']).to include('type' => 'integer', 'format' => 'int64')
  end

  it 'maps a String property to a plain string with no format' do
    expect(properties['label']).to include('type' => 'string')
    expect(properties['label']).not_to have_key('format')
  end

  it 'maps a Date property to string / date' do
    expect(properties['born_on']).to include('type' => 'string', 'format' => 'date')
  end

  it 'maps a DateTime property to string / date-time' do
    expect(properties['seen_at']).to include('type' => 'string', 'format' => 'date-time')
  end

  it 'maps a Boolean property to boolean with no format' do
    expect(properties['active']).to include('type' => 'boolean')
    expect(properties['active']).not_to have_key('format')
  end

  it 'maps an enum property to a $ref rather than a primitive type' do
    expect(properties['status']).to include('$ref' => '#/definitions/SingleScalarStatus')
    expect(properties['status']).not_to have_key('type')
  end
end
