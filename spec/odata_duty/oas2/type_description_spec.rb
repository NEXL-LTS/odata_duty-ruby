require 'spec_helper'

class Oas2TypeDescriptionPeopleResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe OAS2, 'type-level description' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        address = s.add_complex_type(name: 'Address', description: 'A postal address') do |c|
          c.property 'street', String
        end
        person = s.add_entity_type(name: 'Person',
                                   description: 'People present at the event') do |et|
          et.property_ref 'id', String
          et.property 'home', address, nullable: true
        end
        s.add_entity_set(name: 'People', entity_type: person,
                         resolver: 'Oas2TypeDescriptionPeopleResolver')

        plain_type = s.add_complex_type(name: 'Plain') { |c| c.property 'value', String }
        plain_entity = s.add_entity_type(name: 'Plainly') do |et|
          et.property_ref 'id', String
          et.property 'plain', plain_type, nullable: true
        end
        s.add_entity_set(name: 'Plainlies', entity_type: plain_entity,
                         resolver: 'Oas2TypeDescriptionPeopleResolver')
      end
    end

    let(:json) { OAS2.build_json(schema, context: Context.new) }

    it 'includes the description on the complex type definition' do
      expect(json['definitions']['Address']).to include('description' => 'A postal address')
    end

    it 'includes the description on the entity type definition, inherited from ComplexType' do
      expect(json['definitions']['Person'])
        .to include('description' => 'People present at the event')
    end

    it 'omits the description key for a complex type without one' do
      expect(json['definitions']['Plain']).not_to have_key('description')
    end

    it 'omits the description key for an entity type without one' do
      expect(json['definitions']['Plainly']).not_to have_key('description')
    end
  end
end
