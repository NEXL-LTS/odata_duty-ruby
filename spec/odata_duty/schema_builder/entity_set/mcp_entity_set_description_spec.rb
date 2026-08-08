require 'spec_helper'

class McpEntitySetDescriptionResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end

  def count
    @records.count
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

class McpUndescribedEntitySetResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP entity-set-level description' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'McpDescPerson') do |et|
          et.property_ref 'id', String
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'McpEntitySetDescriptionResolver',
                         description: 'Attendees checked in at the front desk')
        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'McpUndescribedEntitySetResolver')
      end
    end

    let(:mcp_server) do
      server = schema.to_mcp_server
      server.server_context = { context: Context.new }
      server
    end

    def call(payload)
      Oj.load(mcp_server.handle_json(Oj.dump(payload)))
    end

    let(:tools) do
      request_payload = { 'jsonrpc' => '2.0', 'method' => 'tools/list', 'params' => {},
                          'id' => 'tl-1' }
      call(request_payload)['result']['tools']
    end

    def tool(name)
      tools.find { |t| t['name'] == name }
    end

    it 'suffixes the list tool description with the entity set description' do
      expect(tool('list_People')['description'])
        .to eq('List People records. Attendees checked in at the front desk')
    end

    it 'suffixes the count tool description with the entity set description' do
      expect(tool('count_People')['description'])
        .to eq('Count People records. Attendees checked in at the front desk')
    end

    it 'suffixes the get tool description with the entity set description' do
      expect(tool('get_People')['description'])
        .to eq('Get a single People record by ID. Attendees checked in at the front desk')
    end

    it 'suffixes the create tool description with the entity set description' do
      expect(tool('create_People')['description'])
        .to eq('Create a new People record. Attendees checked in at the front desk')
    end

    it 'suffixes the update tool description with the entity set description' do
      expect(tool('update_People')['description'])
        .to eq('Update an existing People record. Attendees checked in at the front desk')
    end

    it 'suffixes the delete tool description with the entity set description' do
      expect(tool('delete_People')['description'])
        .to eq('Delete an existing People record. Attendees checked in at the front desk')
    end

    it 'keeps the exact existing tool description for a set without one' do
      expect(tool('list_Widgets')['description']).to eq('List Widgets records')
    end

    it 'keeps the exact existing get tool description for a set without one' do
      expect(tool('get_Widgets')['description']).to eq('Get a single Widgets record by ID')
    end
  end
end
