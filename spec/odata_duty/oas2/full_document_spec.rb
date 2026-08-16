require 'spec_helper'

class FullDocCrudResolver < OdataDuty::SetResolver
  def od_after_init
    @records = []
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end

  def create(input)
    input
  end

  def update(id, input)
    [id, input]
  end

  def delete(id)
    id
  end

  def count
    @records.count
  end

  def od_search(expression)
    expression
  end

  def od_top(top)
    top
  end

  def od_skip(skip)
    skip
  end

  def od_skiptoken(token)
    token
  end
end

class FullDocReadOnlyResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def individual(id)
    id
  end
end

RSpec.describe OdataDuty::OAS2, 'full document contract' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      s.title = 'Full Document Sample Service'
      s.version = '4.5.6'
      status_enum = s.add_enum_type(name: 'FullDocStatus') do |e|
        e.member 'Active'
        e.member 'Inactive'
      end
      badge_complex = s.add_complex_type(name: 'FullDocBadge') do |c|
        c.property 'label', String, nullable: false
      end
      widget_entity = s.add_entity_type(name: 'FullDocWidget') do |et|
        et.property_ref 'id', Integer
        et.property 'name', String, nullable: false
        et.property 'nickname', String
        et.property 'status', status_enum
        et.property 'badge', badge_complex
        et.property 'created_at', DateTime, mutability: :computed
      end
      gadget_entity = s.add_entity_type(name: 'FullDocGadget') do |et|
        et.property_ref 'code', String
        et.property 'title', String, nullable: false
      end

      s.add_entity_set(name: 'FullDocWidgets', entity_type: widget_entity,
                       resolver: 'FullDocCrudResolver')
      s.add_entity_set(name: 'FullDocGadgets', entity_type: gadget_entity,
                       resolver: 'FullDocReadOnlyResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  EXPECTED_FULL_DOC = Oj.load(File.read("#{File.dirname(__FILE__)}/full_document.json"))

  it 'renders the entire Swagger 2.0 document exactly' do
    expect(json).to eq(EXPECTED_FULL_DOC)
  end
end
