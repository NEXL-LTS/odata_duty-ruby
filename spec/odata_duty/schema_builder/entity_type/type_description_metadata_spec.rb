require 'spec_helper'

class TypeDescMetaPersonResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, '$metadata rendering of type-level description' do
    let(:schema) do
      SchemaBuilder.build(namespace: 'DescribedTypesSpace', host: 'localhost') do |s|
        address = s.add_complex_type(name: 'Address', description: 'A postal address') do |c|
          c.property 'street', String
        end
        person = s.add_entity_type(name: 'Person',
                                   description: 'People present at the event') do |et|
          et.property_ref 'id', String
          et.property 'home', address, nullable: true
        end
        s.add_entity_set(name: 'People', entity_type: person,
                         resolver: 'TypeDescMetaPersonResolver')

        undescribed_address = s.add_complex_type(name: 'UndescribedAddress') do |c|
          c.property 'value', String
        end
        undescribed_person = s.add_entity_type(name: 'UndescribedPerson') do |et|
          et.property_ref 'id', String
          et.property 'address', undescribed_address, nullable: true
        end
        s.add_entity_set(name: 'UndescribedPeople', entity_type: undescribed_person,
                         resolver: 'TypeDescMetaPersonResolver')
      end
    end

    let(:xml) { schema.metadata_xml }

    it 'renders the Core Description annotation as the first child of ComplexType' do
      complex_type_index = xml.index('<ComplexType Name="Address">')
      description_index = xml.index(
        '<Annotation Term="Org.OData.Core.V1.Description" String="A postal address" />'
      )
      property_index = xml.index('<Property Name="street"', complex_type_index)
      expect(complex_type_index).to be < description_index
      expect(description_index).to be < property_index
    end

    it 'renders the Core Description annotation as the first child of EntityType, before Key' do
      entity_type_index = xml.index('<EntityType Name="Person">')
      description_index = xml.index(
        '<Annotation Term="Org.OData.Core.V1.Description" ' \
        'String="People present at the event" />'
      )
      key_index = xml.index('<Key>', entity_type_index)
      expect(entity_type_index).to be < description_index
      expect(description_index).to be < key_index
    end

    it 'omits the annotation entirely for a complex type without a description' do
      undescribed_start = xml.index('<ComplexType Name="UndescribedAddress">')
      undescribed_chunk = xml[undescribed_start...(undescribed_start + 300)]
      expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
    end

    it 'omits the annotation entirely for an entity type without a description' do
      undescribed_start = xml.index('<EntityType Name="UndescribedPerson">')
      undescribed_chunk = xml[undescribed_start...(undescribed_start + 300)]
      expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
    end
  end
end
