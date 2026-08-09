require 'spec_helper'

module MetadataEntitySetDescriptionExample
  class Person < OdataDuty::EntityType
    property_ref 'id', String
  end

  class DescribedReadOnlyPeopleSet < OdataDuty::EntitySet
    entity_type Person
    description 'Attendees checked in at the front desk'

    def collection
      []
    end
  end

  class UndescribedReadOnlyPeopleSet < OdataDuty::EntitySet
    entity_type Person

    def collection
      []
    end
  end

  class Schema < OdataDuty::Schema
    namespace 'MetadataEntitySetDescriptionSpace'
    base_url 'http://localhost:3000/api'
    entity_sets [DescribedReadOnlyPeopleSet, UndescribedReadOnlyPeopleSet]
  end
end

RSpec.describe OdataDuty::EntitySet, '$metadata rendering of entity-set-level description' do
  let(:xml) { MetadataEntitySetDescriptionExample::Schema.metadata_xml }

  it 'produces well-formed XML' do
    doc = Nokogiri::XML(xml)
    expect(doc.errors).to be_empty
  end

  it 'renders the Core Description annotation inside the described EntitySet element' do
    set_start = xml.index('<EntitySet Name="DescribedReadOnlyPeople"')
    set_end = xml.index('</EntitySet>', set_start)
    description_index = xml.index(
      '<Annotation Term="Org.OData.Core.V1.Description" ' \
      'String="Attendees checked in at the front desk" />'
    )
    expect(set_start).to be < description_index
    expect(description_index).to be < set_end
  end

  it 'still renders the InsertRestrictions/UpdateRestrictions/DeleteRestrictions annotations ' \
     'for the described read-only set' do
    set_start = xml.index('<EntitySet Name="DescribedReadOnlyPeople"')
    set_end = xml.index('</EntitySet>', set_start)
    chunk = xml[set_start...set_end]
    expect(chunk).to include('Capabilities.InsertRestrictions')
    expect(chunk).to include('Capabilities.UpdateRestrictions')
    expect(chunk).to include('Capabilities.DeleteRestrictions')
  end

  it 'omits the Description annotation entirely for an entity set without one' do
    set_start = xml.index('<EntitySet Name="UndescribedReadOnlyPeople"')
    set_end = xml.index('</EntitySet>', set_start)
    chunk = xml[set_start...set_end]
    expect(chunk).not_to include('Org.OData.Core.V1.Description')
  end

  it 'still renders the capability annotations for the undescribed read-only set' do
    set_start = xml.index('<EntitySet Name="UndescribedReadOnlyPeople"')
    set_end = xml.index('</EntitySet>', set_start)
    chunk = xml[set_start...set_end]
    expect(chunk).to include('Capabilities.InsertRestrictions')
    expect(chunk).to include('Capabilities.UpdateRestrictions')
    expect(chunk).to include('Capabilities.DeleteRestrictions')
  end
end
