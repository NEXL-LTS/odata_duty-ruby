require 'spec_helper'

class NonInsertableNamesResolver < OdataDuty::SetResolver
  def collection = []
  def create(_input); end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'reports non-insertable property names in metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'Widget') do |et|
          et.property_ref 'id', String
          et.property 'status', String, mutability: :non_insertable
          et.property 'label', String, mutability: :read_write
          et.property 'code', String, mutability: :non_insertable
        end
        s.add_entity_set(name: 'Widgets', entity_type: entity,
                         resolver: 'NonInsertableNamesResolver')
      end.metadata_xml
    end

    def non_insertable_property_paths
      set_xml = metadata_xml.split('<EntitySet Name="Widgets"')[1].split('</EntitySet>')[0]
      doc = Nokogiri::XML("<root>#{set_xml}</root>")
      doc.xpath('//Annotation[@Term="Capabilities.InsertRestrictions"]' \
                '//PropertyValue[@Property="NonInsertableProperties"]' \
                '/Collection/PropertyPath').map(&:text)
    end

    it 'lists exactly the non-insertable property names as PropertyPath entries' do
      expect(non_insertable_property_paths).to eq(%w[status code])
    end

    it 'excludes read_write and key properties from the non-insertable list' do
      expect(non_insertable_property_paths).not_to include('label', 'id')
    end
  end
end
