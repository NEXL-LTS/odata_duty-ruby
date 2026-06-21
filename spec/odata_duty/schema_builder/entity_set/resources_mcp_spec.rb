require 'spec_helper'

class ResourcesMcpWidgetResolver < OdataDuty::SetResolver
  WIDGETS = [Struct.new(:id, :name).new('1', 'First'),
             Struct.new(:id, :name).new('2', 'Second')].freeze

  def collection
    WIDGETS
  end

  def individual(id)
    WIDGETS.find { |w| w.id == id }
  end

  def count
    WIDGETS.count
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'MCP resources/read' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'ResourcesMcpWidgetEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'ResourcesMcpWidgetResolver')
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

    def read(uri)
      call('jsonrpc' => '2.0', 'method' => 'resources/read',
           'params' => { 'uri' => uri }, 'id' => 'r-1')['result']['contents'][0]
    end

    it 'reads a specific record as OData JSON' do
      contents = read("Widgets('1')")

      expect(contents['mimeType']).to eq('application/json')
      expect(Oj.load(contents['text'])).to include('id' => '1', 'name' => 'First')
    end

    it 'reads a count resource as a text/plain string' do
      contents = read('Widgets/$count')

      expect(contents['uri']).to eq('Widgets/$count')
      expect(contents['mimeType']).to eq('text/plain')
      expect(contents['text']).to eq('2')
    end
  end
end
