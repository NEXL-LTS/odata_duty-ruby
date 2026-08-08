require 'spec_helper'

class MetadataDescriptionAddress < OdataDuty::ComplexType
  property 'street', String, description: 'Street line, including house number'
end

class MetadataDescriptionEntity < OdataDuty::EntityType
  property_ref 'id', String, description: 'Server-assigned identifier'
  property 'name', String, description: 'First name or "full" name & more'
  property 'plain', String
  property 'address', MetadataDescriptionAddress
  property 'tags', [String], description: 'Free-form labels attached to the record'
end

class MetadataDescriptionSet < OdataDuty::EntitySet
  entity_type MetadataDescriptionEntity
end

class MetadataDescriptionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [MetadataDescriptionSet]
end

RSpec.describe OdataDuty::Schema, 'Property description metadata' do
  subject(:metadata_xml) { MetadataDescriptionSchema.metadata_xml }

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

  it 'renders the Core Description annotation for a described collection property' do
    expect(property_xml('tags'))
      .to include('<Annotation Term="Org.OData.Core.V1.Description" ' \
                  'String="Free-form labels attached to the record" />')
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
