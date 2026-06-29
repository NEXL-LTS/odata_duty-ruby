require 'spec_helper'

class NonInsertableMetadataEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'status', String, mutability: :non_insertable
  property 'name', String, mutability: :read_write
end

class NonInsertableMetadataSet < OdataDuty::EntitySet
  entity_type NonInsertableMetadataEntity

  def collection; end
  def create(_input); end
end

class NonInsertableNoCreateEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'status', String, mutability: :non_insertable
end

class NonInsertableNoCreateSet < OdataDuty::EntitySet
  entity_type NonInsertableNoCreateEntity

  def collection; end
end

class PlainCreateEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String, mutability: :read_write
end

class PlainCreateSet < OdataDuty::EntitySet
  entity_type PlainCreateEntity

  def collection; end
  def create(_input); end
end

class NonInsertableMetadataSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [NonInsertableMetadataSet, NonInsertableNoCreateSet, PlainCreateSet]
end

RSpec.describe OdataDuty::Schema, 'Non-insertable property metadata' do
  subject(:metadata_xml) { NonInsertableMetadataSchema.metadata_xml }

  def entity_set_xml(name)
    metadata_xml.split(%(<EntitySet Name="#{name}"))[1].split('</EntitySet>')[0]
  end

  def insert_restrictions(name)
    xml = entity_set_xml(name)
    doc = Nokogiri::XML("<root>#{xml}</root>")
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
