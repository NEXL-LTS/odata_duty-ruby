require 'spec_helper'

class ImmutableMetadataBuilderResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'Immutable property metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'ImmutableMetadataEntity') do |et|
          et.property_ref 'id', String
          et.property 'account_number', String, mutability: :immutable
          et.property 'created_at', DateTime, mutability: :computed
          et.property 'name', String, mutability: :read_write
        end

        s.add_entity_set(name: 'ImmutableMetadata', entity_type: entity,
                         resolver: 'ImmutableMetadataBuilderResolver')
      end.metadata_xml
    end

    def property_xml(name)
      metadata_xml.split(%(<Property Name="#{name}"))[1].split('<Property ')[0]
    end

    it 'renders the Core Immutable annotation for an immutable property' do
      expect(property_xml('account_number'))
        .to include('<Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />')
    end

    it 'does not render the Computed annotation for an immutable property' do
      expect(property_xml('account_number')).not_to include('Org.OData.Core.V1.Computed')
    end

    it 'renders the Computed annotation for a computed property' do
      expect(property_xml('created_at'))
        .to include('<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />')
    end

    it 'does not render the Immutable annotation for a computed property' do
      expect(property_xml('created_at')).not_to include('Org.OData.Core.V1.Immutable')
    end

    it 'renders neither annotation for a read_write property' do
      expect(property_xml('name')).not_to include('Org.OData.Core.V1.Immutable')
      expect(property_xml('name')).not_to include('Org.OData.Core.V1.Computed')
    end

    it 'produces well-formed XML' do
      doc = Nokogiri::XML(metadata_xml)
      expect(doc.errors).to be_empty
    end

    it 'renders the read_write property as a clean element with no stray markup' do
      expect(property_xml('name')).not_to include('> />')
      expect(property_xml('name')).not_to include('></Property>')
    end
  end
end
