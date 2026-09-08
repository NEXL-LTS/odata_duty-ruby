require 'spec_helper'

class Oas2RequiredInitArgsResolver < OdataDuty::SetResolver
  def od_after_init(page_size:)
    @page_size = page_size
    @records = []
  end

  def collection
    @records
  end

  def od_top(top)
    @records = @records[0...[top.to_i, @page_size].min]
  end

  def od_skip(skip)
    @records = @records[skip.to_i..]
  end
end

RSpec.describe OdataDuty::OAS2, 'collection GET for an entity set declared with init_args' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
      person = s.add_entity_type(name: 'Oas2InitArgsPerson') do |et|
        et.property_ref 'id', String
        et.property 'user_name', String
      end

      s.add_entity_set(name: 'PagedPeople', entity_type: person,
                       resolver: 'Oas2RequiredInitArgsResolver',
                       init_args: { page_size: 10 })
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  it 'builds the document, passing the init_args on to the resolver it probes for support' do
    expect(json.dig('paths', '/PagedPeople', 'get', 'parameters').map { |param| param['name'] })
      .to eq(['$select', '$top', '$skip'])
  end
end
