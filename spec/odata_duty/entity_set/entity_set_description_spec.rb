require 'spec_helper'

module EntitySetDescriptionValidationExample
  class Person < OdataDuty::EntityType
    property_ref 'id', String
  end

  class People < OdataDuty::EntitySet
    entity_type Person
    description 'Attendees checked in at the front desk'

    def collection
      []
    end
  end

  class Undescribed < OdataDuty::EntitySet
    entity_type Person

    def collection
      []
    end
  end
end

RSpec.describe OdataDuty::EntitySet, 'entity-set-level description validation' do
  it 'reads back the exact description declared on an entity set' do
    expect(EntitySetDescriptionValidationExample::People.description)
      .to eq('Attendees checked in at the front desk')
  end

  it 'treats omitted description as no description on an entity set' do
    expect(EntitySetDescriptionValidationExample::Undescribed.description).to be_nil
  end

  it 'exposes the description via EntitySet::Metadata' do
    expect(EntitySetDescriptionValidationExample::People.__metadata.description)
      .to eq('Attendees checked in at the front desk')
  end

  it 'raises InvalidDescriptionError naming the set for an empty string' do
    expect do
      class InvalidDescriptionPeopleSet < OdataDuty::EntitySet
        entity_type EntitySetDescriptionValidationExample::Person
        description ''
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'InvalidDescriptionPeople: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      class WhitespaceDescriptionPeopleSet < OdataDuty::EntitySet
        entity_type EntitySetDescriptionValidationExample::Person
        description '   '
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'WhitespaceDescriptionPeople: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      class SymbolDescriptionPeopleSet < OdataDuty::EntitySet
        entity_type EntitySetDescriptionValidationExample::Person
        description :people
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'SymbolDescriptionPeople: description must be a non-empty string')
  end
end
