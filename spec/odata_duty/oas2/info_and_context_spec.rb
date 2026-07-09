require 'spec_helper'

class OAS2DocMinimalResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

RSpec.describe OdataDuty::OAS2, 'info block and context handling' do
  def build_schema(&block)
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      block&.call(s)
      entity = s.add_entity_type(name: 'OAS2DocMinimalEntity') do |et|
        et.property_ref 'id', String
      end
      s.add_entity_set(name: 'OAS2DocMinimals', entity_type: entity,
                       resolver: 'OAS2DocMinimalResolver')
    end
  end

  it 'renders an empty info block when neither version nor title is set' do
    json = OdataDuty::OAS2.build_json(build_schema, context: Context.new)
    expect(json['info']).to eq({})
  end

  it 'renders only version in info when only version is set' do
    schema = build_schema { |s| s.version = '9.9.9' }
    json = OdataDuty::OAS2.build_json(schema, context: Context.new)
    expect(json['info']).to eq({ 'version' => '9.9.9' })
  end

  it 'renders only title in info when only title is set' do
    schema = build_schema { |s| s.title = 'Only Title Service' }
    json = OdataDuty::OAS2.build_json(schema, context: Context.new)
    expect(json['info']).to eq({ 'title' => 'Only Title Service' })
  end

  it 'renders the document without a context argument' do
    json = OdataDuty::OAS2.build_json(build_schema)
    expect(json.keys)
      .to contain_exactly('swagger', 'info', 'host', 'schemes', 'basePath', 'paths', 'definitions')
  end
end
