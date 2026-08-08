require 'spec_helper'

class Oas2EnumDescriptionPeopleResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EnumType, 'enum type-level description via OAS2.build_json' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        gender = s.add_enum_type(name: 'Gender',
                                 description: 'Gender as recorded at registration') do |e|
          e.member 'Male', description: 'Recorded as male'
          e.member 'Female', description: 'Recorded as female'
        end
        person = s.add_entity_type(name: 'Person') do |et|
          et.property_ref 'id', String
          et.property 'gender', gender, nullable: true
        end
        s.add_entity_set(name: 'People', entity_type: person,
                         resolver: 'Oas2EnumDescriptionPeopleResolver')

        plain = s.add_enum_type(name: 'Plain') { |e| e.member 'One' }
        plainly = s.add_entity_type(name: 'Plainly') do |et|
          et.property_ref 'id', String
          et.property 'plain', plain, nullable: true
        end
        s.add_entity_set(name: 'Plainlies', entity_type: plainly,
                         resolver: 'Oas2EnumDescriptionPeopleResolver')
      end
    end

    let(:json) { OAS2.build_json(schema, context: Context.new) }

    it 'renders the enum type definition with the description alongside its values' do
      expect(json['definitions']['Gender']).to eq(
        'type' => 'string',
        'enum' => %w[Male Female],
        'description' => 'Gender as recorded at registration'
      )
    end

    it 'renders the enum type definition without a description key when there is none' do
      expect(json['definitions']['Plain']).to eq('type' => 'string', 'enum' => ['One'])
    end
  end
end
