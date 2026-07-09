require 'spec_helper'

class CollectionScalarsOas2Resolver < OdataDuty::SetResolver
  def collection
    []
  end
end

RSpec.describe OdataDuty::OAS2, 'collection scalar property definitions' do
  let(:oas2_schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'CollectionScalarsOas2Entity') do |et|
        et.property_ref 'id', String
        et.property 'ints', [Integer]
        et.property 'strings', [String]
        et.property 'dates', [Date]
        et.property 'datetimes', [DateTime]
        et.property 'bools', [TrueClass]
        et.property 'single_date', Date
        et.property 'single_bool', TrueClass
      end

      s.add_entity_set(name: 'CollectionScalarsOas2', entity_type: entity,
                       resolver: 'CollectionScalarsOas2Resolver')
    end
  end

  let(:properties) do
    OdataDuty::OAS2.build_json(oas2_schema, context: Context.new)
                   .dig('definitions', 'CollectionScalarsOas2Entity', 'properties')
  end

  it 'renders an array of int64 for an Integer collection' do
    expect(properties['ints'])
      .to include('type' => 'array', 'items' => { 'type' => 'integer', 'format' => 'int64' })
  end

  it 'renders an array of strings for a String collection' do
    expect(properties['strings'])
      .to include('type' => 'array', 'items' => { 'type' => 'string' })
  end

  it 'renders an array of dates for a Date collection' do
    expect(properties['dates'])
      .to include('type' => 'array', 'items' => { 'type' => 'string', 'format' => 'date' })
  end

  it 'renders an array of date-times for a DateTime collection' do
    expect(properties['datetimes'])
      .to include('type' => 'array',
                  'items' => { 'type' => 'string', 'format' => 'date-time' })
  end

  it 'renders an array of booleans for a Boolean collection' do
    expect(properties['bools'])
      .to include('type' => 'array', 'items' => { 'type' => 'boolean' })
  end

  it 'renders a scalar date property' do
    expect(properties['single_date']).to include('type' => 'string', 'format' => 'date')
  end

  it 'renders a scalar boolean property' do
    expect(properties['single_bool']).to include('type' => 'boolean')
  end
end
