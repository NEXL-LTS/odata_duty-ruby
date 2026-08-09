require 'spec_helper'

class DescribedReadOnlyEntitySetResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, '$metadata rendering of description' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'BuilderEntitySetDescSpace', host: 'localhost',
                          base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'DescPerson') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'DescribedReadOnlyPeople', entity_type: entity,
                         resolver: 'DescribedReadOnlyEntitySetResolver',
                         description: 'Attendees checked in at the front desk')
        s.add_entity_set(name: 'UndescribedReadOnlyPeople', entity_type: entity,
                         resolver: 'DescribedReadOnlyEntitySetResolver')
      end.metadata_xml
    end

    def entity_set_xml(name)
      set_start = metadata_xml.index(%(<EntitySet Name="#{name}"))
      set_end = metadata_xml.index('</EntitySet>', set_start)
      metadata_xml[set_start...set_end]
    end

    it 'renders the Core Description annotation inside the described EntitySet element' do
      expect(entity_set_xml('DescribedReadOnlyPeople'))
        .to include('<Annotation Term="Org.OData.Core.V1.Description" ' \
                    'String="Attendees checked in at the front desk" />')
    end

    it 'still renders the read-only capability annotations alongside the description' do
      chunk = entity_set_xml('DescribedReadOnlyPeople')
      expect(chunk).to include('Capabilities.InsertRestrictions')
      expect(chunk).to include('Capabilities.UpdateRestrictions')
      expect(chunk).to include('Capabilities.DeleteRestrictions')
    end

    it 'omits the Description annotation entirely for an entity set without one' do
      expect(entity_set_xml('UndescribedReadOnlyPeople'))
        .not_to include('Org.OData.Core.V1.Description')
    end

    it 'still renders the read-only capability annotations without a description' do
      chunk = entity_set_xml('UndescribedReadOnlyPeople')
      expect(chunk).to include('Capabilities.InsertRestrictions')
      expect(chunk).to include('Capabilities.UpdateRestrictions')
      expect(chunk).to include('Capabilities.DeleteRestrictions')
    end

    it 'produces well-formed XML' do
      doc = Nokogiri::XML(metadata_xml)
      expect(doc.errors).to be_empty
    end
  end
end
