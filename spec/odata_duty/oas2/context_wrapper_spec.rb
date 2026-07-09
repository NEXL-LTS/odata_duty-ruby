require 'spec_helper'

class OAS2DocContextReadingResolver < OdataDuty::SetResolver
  def od_after_init
    @seen_url = context.od_full_url('items')
    @seen_options = context.query_options
    @seen_entity_set = context.endpoint.entity_set.name
    @seen_caller = context.members
    @records = []
  end

  def collection
    @records
  end
end

RSpec.describe OdataDuty::OAS2, 'context wrapper for collection rendering' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      entity = s.add_entity_type(name: 'OAS2DocContextEntity') do |et|
        et.property_ref 'id', String
      end
      s.add_entity_set(name: 'OAS2DocContexts', entity_type: entity,
                       resolver: 'OAS2DocContextReadingResolver')
    end
  end

  it 'wraps the context so resolver init can read url, options, and endpoint' do
    json = OdataDuty::OAS2.build_json(schema, context: Context.new)
    expect(json.dig('paths', '/OAS2DocContexts', 'get', 'operationId'))
      .to eq('GetCollectionOfOAS2DocContexts')
  end
end
