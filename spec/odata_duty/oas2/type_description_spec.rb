require 'spec_helper'

class Oas2TypeDescriptionPeopleResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::ComplexType, 'type-level description via OAS2.build_json' do
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

    it 'renders the complex type definition with the description alongside its properties' do
      expect(json['definitions']['Address']).to eq(
        'type' => 'object',
        'description' => 'A postal address',
        'properties' => { 'street' => { 'type' => 'string', 'x-nullable' => true } }
      )
    end

    it 'renders the entity type definition with the description, inherited from ComplexType' do
      expect(json['definitions']['Person']).to eq(
        'type' => 'object',
        'description' => 'People present at the event',
        'properties' => {
          'id' => { 'type' => 'string', 'readOnly' => true },
          'home' => { '$ref' => '#/definitions/Address', 'x-nullable' => true }
        }
      )
    end

    it 'renders the complex type definition without a description key when there is none' do
      expect(json['definitions']['Plain']).to eq(
        'type' => 'object',
        'properties' => { 'value' => { 'type' => 'string', 'x-nullable' => true } }
      )
    end

    it 'renders the entity type definition without a description key when there is none' do
      expect(json['definitions']['Plainly']).to eq(
        'type' => 'object',
        'properties' => {
          'id' => { 'type' => 'string', 'readOnly' => true },
          'plain' => { '$ref' => '#/definitions/Plain', 'x-nullable' => true }
        }
      )
    end
  end
end
