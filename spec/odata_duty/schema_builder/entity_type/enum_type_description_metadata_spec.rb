require 'spec_helper'

class EnumDescMetaPersonResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, '$metadata rendering of enum type-level description' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'DescribedEnumSpace', host: 'localhost') do |s|
        gender = s.add_enum_type(name: 'Gender',
                                 description: 'Gender as recorded at registration') do |e|
          e.member 'Male', description: 'Recorded as male'
          e.member 'Female'
        end
        person = s.add_entity_type(name: 'Person') do |et|
          et.property_ref 'id', String
          et.property 'gender', gender, nullable: true
        end
        s.add_entity_set(name: 'People', entity_type: person,
                         resolver: 'EnumDescMetaPersonResolver')

        plain = s.add_enum_type(name: 'Plain') { |e| e.member 'One' }
        plainly = s.add_entity_type(name: 'Plainly') do |et|
          et.property_ref 'id', String
          et.property 'plain', plain, nullable: true
        end
        s.add_entity_set(name: 'Plainlies', entity_type: plainly,
                         resolver: 'EnumDescMetaPersonResolver')
      end
    end

    let(:xml) { schema.metadata_xml }

    it 'renders the Core Description annotation as the first child of EnumType' do
      enum_type_index = xml.index('<EnumType Name="Gender">')
      description_index = xml.index(
        '<Annotation Term="Org.OData.Core.V1.Description" ' \
        'String="Gender as recorded at registration" />'
      )
      member_index = xml.index('<Member Name="Male"', enum_type_index)
      expect(enum_type_index).to be < description_index
      expect(description_index).to be < member_index
    end

    it 'omits the annotation entirely for an enum type without a description' do
      undescribed_start = xml.index('<EnumType Name="Plain">')
      undescribed_chunk = xml[undescribed_start...(undescribed_start + 200)]
      expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
    end

    it 'renders a Description annotation as a child of a described member' do
      male_index = xml.index('<Member Name="Male">')
      description_index = xml.index(
        '<Annotation Term="Org.OData.Core.V1.Description" String="Recorded as male" />'
      )
      female_index = xml.index('<Member Name="Female"')
      expect(male_index).to be < description_index
      expect(description_index).to be < female_index
    end

    it 'keeps an undescribed member self-closed' do
      expect(xml).to include('<Member Name="Female" />')
    end
  end
end
