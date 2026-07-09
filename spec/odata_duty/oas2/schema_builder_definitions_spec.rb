require 'spec_helper'

class DefsWidgetsResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class DefsReadonlyResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder, '$oas2 definitions and collection path selection' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        status = s.add_enum_type(name: 'DefsStatus') do |e|
          e.member 'Active'
          e.member 'Inactive'
        end
        badge = s.add_complex_type(name: 'DefsBadge') do |c|
          c.property 'label', String, nullable: false
          c.property 'rank', Integer
        end
        widget = s.add_entity_type(name: 'DefsWidget') do |et|
          et.property_ref 'id', String
          et.property 'status', status
          et.property 'badge', badge
        end
        s.add_entity_set(name: 'DefsWidgets', entity_type: widget, resolver: 'DefsWidgetsResolver')
        s.add_entity_set(name: 'DefsReadonly', entity_type: widget,
                         resolver: 'DefsReadonlyResolver')
      end
    end

    let(:json) { OAS2.build_json(schema, context: Context.new) }

    it 'renders an enum type as a string with its members' do
      expect(json['definitions']['DefsStatus'])
        .to eq('type' => 'string', 'enum' => %w[Active Inactive])
    end

    it 'renders a complex type as an object keyed by its property names' do
      expect(json['definitions']['DefsBadge']).to eq(
        'type' => 'object',
        'properties' => {
          'label' => { 'type' => 'string' },
          'rank' => { 'type' => 'integer', 'format' => 'int64', 'x-nullable' => true }
        }
      )
    end

    it 'exposes a collection GET path only for sets whose resolver defines collection' do
      expect(json['paths'].keys).to include('/DefsWidgets')
      expect(json['paths'].keys).not_to include('/DefsReadonly')
    end
  end
end
