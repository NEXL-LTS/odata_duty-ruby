require 'spec_helper'

class NonInsertableBuilderResolver < OdataDuty::SetResolver
  def collection; end
  def create(_input); end
end

class NonInsertableNoCreateBuilderResolver < OdataDuty::SetResolver
  def collection; end
end

class PlainCreateBuilderResolver < OdataDuty::SetResolver
  def collection; end
  def create(_input); end
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'Non-insertable property metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        with_create = s.add_entity_type(name: 'NonInsertableMetadataEntity') do |et|
          et.property_ref 'id', String
          et.property 'status', String, mutability: :non_insertable
          et.property 'name', String, mutability: :read_write
        end
        no_create = s.add_entity_type(name: 'NonInsertableNoCreateEntity') do |et|
          et.property_ref 'id', String
          et.property 'status', String, mutability: :non_insertable
        end
        plain = s.add_entity_type(name: 'PlainCreateEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String, mutability: :read_write
        end

        s.add_entity_set(name: 'NonInsertableMetadata', entity_type: with_create,
                         resolver: 'NonInsertableBuilderResolver')
        s.add_entity_set(name: 'NonInsertableNoCreate', entity_type: no_create,
                         resolver: 'NonInsertableNoCreateBuilderResolver')
        s.add_entity_set(name: 'PlainCreate', entity_type: plain,
                         resolver: 'PlainCreateBuilderResolver')
      end.metadata_xml
    end

    def entity_set_xml(name)
      metadata_xml.split(%(<EntitySet Name="#{name}"))[1].split('</EntitySet>')[0]
    end

    def insert_restrictions(name)
      doc = Nokogiri::XML("<root>#{entity_set_xml(name)}</root>")
      doc.xpath('//Annotation[@Term="Capabilities.InsertRestrictions"]')
    end

    it 'emits the non-insertable property as a PropertyPath in NonInsertableProperties' do
      annotation = insert_restrictions('NonInsertableMetadata')
      expect(annotation.xpath('.//PropertyValue[@Property="NonInsertableProperties"]' \
                              '/Collection/PropertyPath').map(&:text)).to eq(['status'])
    end

    it 'does not emit Insertable false when the set supports create' do
      annotation = insert_restrictions('NonInsertableMetadata')
      expect(annotation.xpath('.//PropertyValue[@Property="Insertable"]')).to be_empty
    end

    it 'composes NonInsertableProperties with Insertable false in one Record' do
      annotation = insert_restrictions('NonInsertableNoCreate')
      record = annotation.xpath('./Record')
      expect(record.size).to eq(1)
      expect(record.xpath('./PropertyValue[@Property="Insertable"]/@Bool').map(&:value))
        .to eq(['false'])
      expect(record.xpath('.//PropertyValue[@Property="NonInsertableProperties"]' \
                          '/Collection/PropertyPath').map(&:text)).to eq(['status'])
    end

    it 'does not add a property-level Core annotation to a non-insertable property' do
      property = metadata_xml.split('<Property Name="status"')[1].split('<Property ')[0]
      expect(property).not_to include('<Annotation')
    end

    it 'emits no InsertRestrictions for a set with create and no non-insertable property' do
      expect(insert_restrictions('PlainCreate')).to be_empty
    end

    it 'produces well-formed XML' do
      expect(Nokogiri::XML(metadata_xml).errors).to be_empty
    end
  end
end
