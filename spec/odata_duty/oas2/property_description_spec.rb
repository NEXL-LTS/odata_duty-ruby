require 'spec_helper'

class Oas2DescriptionPeopleResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def individual(_id)
    nil
  end

  def create(input)
    input
  end

  def update(_id, input)
    input
  end
end

module OdataDuty
  RSpec.describe OAS2, 'property description' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        person = s.add_entity_type(name: 'Person') do |et|
          et.property_ref 'id', String, description: 'Server-assigned identifier'
          et.property 'user_name', String, nullable: false,
                                           description: 'Unique login handle'
          et.property 'plain', String
        end
        s.add_entity_set(name: 'People', entity_type: person,
                         resolver: 'Oas2DescriptionPeopleResolver')
      end
    end

    let(:json) { OAS2.build_json(schema, context: Context.new) }

    it 'includes the property description in the Person definition' do
      expect(json['definitions']['Person']['properties']['user_name'])
        .to include('description' => 'Unique login handle')
    end

    it 'omits the description key for a property without one' do
      expect(json['definitions']['Person']['properties']['plain']).not_to have_key('description')
    end

    it 'includes the property description in the PersonCreate request body definition' do
      expect(json['definitions']['PersonCreate']['properties']['user_name'])
        .to include('description' => 'Unique login handle')
    end

    it 'includes the property description in the PersonUpdate request body definition' do
      expect(json['definitions']['PersonUpdate']['properties']['user_name'])
        .to include('description' => 'Unique login handle')
    end
  end
end
