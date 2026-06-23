require 'spec_helper'

class ComputedMetadataBuilderResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'Computed property metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'ComputedMetadataEntity') do |et|
          et.property_ref 'id', String
          et.property 'created_at', DateTime, computed: true
          et.property 'name', String
        end

        s.add_entity_set(name: 'ComputedMetadata', entity_type: entity,
                         resolver: 'ComputedMetadataBuilderResolver')
      end.metadata_xml
    end

    def property_xml(name)
      metadata_xml.split(%(<Property Name="#{name}"))[1].split('<Property ')[0]
    end

    it 'renders the Core Computed annotation for a computed property' do
      expect(property_xml('created_at'))
        .to include('<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />')
    end

    it 'does not render the Computed annotation for a writable property' do
      expect(property_xml('name')).not_to include('Org.OData.Core.V1.Computed')
    end

    it 'renders the Computed annotation for the entity key by default' do
      expect(property_xml('id'))
        .to include('<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />')
    end

    it 'includes the Core vocabulary reference and include' do
      expect(metadata_xml).to include(
        '<edmx:Reference Uri="https://docs.oasis-open.org/odata/odata-vocabularies/' \
        'v4.0/vocabularies/Org.OData.Core.V1.xml">'
      )
      expect(metadata_xml).to include(
        '<edmx:Include Namespace="Org.OData.Core.V1" Alias="Core" />'
      )
    end
  end
end
