require 'spec_helper'

class Oas2EntitySetDescriptionPeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'Ada')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end

  def create(params)
    params
  end

  def update(_id, params)
    params
  end

  def delete(id)
    @records.find { |r| r.id == id }
  end
end

class Oas2UndescribedEntitySetResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def individual(id)
    id
  end
end

RSpec.describe OdataDuty::OAS2, 'entity-set-level description' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      person = s.add_entity_type(name: 'Oas2DescPerson') do |et|
        et.property_ref 'id', String
        et.property 'name', String, nullable: false
      end
      s.add_entity_set(name: 'People', entity_type: person,
                       resolver: 'Oas2EntitySetDescriptionPeopleResolver',
                       description: 'Attendees checked in at the front desk')

      widget = s.add_entity_type(name: 'Oas2UndescribedWidget') do |et|
        et.property_ref 'id', String
      end
      s.add_entity_set(name: 'Widgets', entity_type: widget,
                       resolver: 'Oas2UndescribedEntitySetResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  describe 'a described entity set' do
    it 'sets the collection GET summary to the same verb text as the list MCP tool' do
      expect(json.dig('paths', '/People', 'get', 'summary')).to eq('List People records')
    end

    it 'sets the collection GET description to the entity set description' do
      expect(json.dig('paths', '/People', 'get', 'description'))
        .to eq('Attendees checked in at the front desk')
    end

    it 'sets the collection POST summary to the same verb text as the create MCP tool' do
      expect(json.dig('paths', '/People', 'post', 'summary')).to eq('Create a new People record')
    end

    it 'sets the collection POST description to the entity set description' do
      expect(json.dig('paths', '/People', 'post', 'description'))
        .to eq('Attendees checked in at the front desk')
    end

    it 'sets the individual GET summary to the same verb text as the get MCP tool' do
      expect(json.dig('paths', '/People({id})', 'get', 'summary'))
        .to eq('Get a single People record by ID')
    end

    it 'sets the individual GET description to the entity set description' do
      expect(json.dig('paths', '/People({id})', 'get', 'description'))
        .to eq('Attendees checked in at the front desk')
    end

    it 'sets the PATCH summary to the same verb text as the update MCP tool' do
      expect(json.dig('paths', '/People({id})', 'patch', 'summary'))
        .to eq('Update an existing People record')
    end

    it 'sets the PATCH description to the entity set description' do
      expect(json.dig('paths', '/People({id})', 'patch', 'description'))
        .to eq('Attendees checked in at the front desk')
    end

    it 'sets the DELETE summary to the same verb text as the delete MCP tool' do
      expect(json.dig('paths', '/People({id})', 'delete', 'summary'))
        .to eq('Delete an existing People record')
    end

    it 'sets the DELETE description to the entity set description' do
      expect(json.dig('paths', '/People({id})', 'delete', 'description'))
        .to eq('Attendees checked in at the front desk')
    end
  end

  describe 'an undescribed entity set (regression: byte-identical to pre-description output)' do
    it 'emits no summary or description key on the collection GET operation' do
      get = json.dig('paths', '/Widgets', 'get')
      expect(get).not_to have_key('summary')
      expect(get).not_to have_key('description')
    end

    it 'emits no summary or description key on the individual GET operation' do
      get = json.dig('paths', '/Widgets({id})', 'get')
      expect(get).not_to have_key('summary')
      expect(get).not_to have_key('description')
    end
  end

  it 'keeps the $oas2 summary identical to the MCP tool description verb portion' do
    mcp_server = schema.to_mcp_server
    mcp_server.server_context = { context: Context.new }
    request_payload = { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {}, 'id' => 1 }
    tools = Oj.load(mcp_server.handle_json(Oj.dump(request_payload)))['result']['tools']

    list_tool = tools.find { |t| t['name'] == 'list_People' }
    update_tool = tools.find { |t| t['name'] == 'update_People' }
    delete_tool = tools.find { |t| t['name'] == 'delete_People' }

    expect(json.dig('paths', '/People', 'get', 'summary'))
      .to eq(list_tool['description'].split('. ').first)
    expect(json.dig('paths', '/People({id})', 'patch', 'summary'))
      .to eq(update_tool['description'].split('. ').first)
    expect(json.dig('paths', '/People({id})', 'delete', 'summary'))
      .to eq(delete_tool['description'].split('. ').first)
  end
end
