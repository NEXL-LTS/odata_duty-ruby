require 'spec_helper'

class BuilderPropertyDescriptionResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'Property description metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        address = s.add_complex_type(name: 'DescribedAddress') do |c|
          c.property 'street', String, description: 'Street line, including house number'
        end
        entity = s.add_entity_type(name: 'DescribedEntity') do |et|
          et.property_ref 'id', String, description: 'Server-assigned identifier'
          et.property 'name', String, description: 'First name or "full" name & more'
          et.property 'plain', String
          et.property 'address', address
        end

        s.add_entity_set(name: 'DescribedEntitySet', entity_type: entity,
                         resolver: 'BuilderPropertyDescriptionResolver')
      end.metadata_xml
    end

    def property_xml(name)
      metadata_xml.split(%(<Property Name="#{name}"))[1].split('<Property ')[0]
    end

    it 'renders the Core Description annotation for a described entity-type property' do
      expect(property_xml('name'))
        .to include('<Annotation Term="Org.OData.Core.V1.Description" ' \
                    'String="First name or &quot;full&quot; name &amp; more" />')
    end

    it 'renders the Core Description annotation for a described complex-type property' do
      expect(property_xml('street'))
        .to include('<Annotation Term="Org.OData.Core.V1.Description" ' \
                    'String="Street line, including house number" />')
    end

    it 'renders no Description annotation for a property without one' do
      expect(property_xml('plain')).not_to include('Org.OData.Core.V1.Description')
    end

    it 'renders the Description before the Computed annotation, both present' do
      xml = property_xml('id')
      description_index = xml.index('Org.OData.Core.V1.Description')
      computed_index = xml.index('Org.OData.Core.V1.Computed')
      expect(description_index).not_to be_nil
      expect(computed_index).not_to be_nil
      expect(description_index).to be < computed_index
    end

    it 'produces well-formed XML' do
      doc = Nokogiri::XML(metadata_xml)
      expect(doc.errors).to be_empty
    end
  end
end
