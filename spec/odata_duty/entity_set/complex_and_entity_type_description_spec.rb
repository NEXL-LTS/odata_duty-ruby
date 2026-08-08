require 'spec_helper'

module ComplexTypeDescriptionValidationExample
  class Address < OdataDuty::ComplexType
    description 'A postal address'
  end
end

RSpec.describe OdataDuty::ComplexType, 'type-level description validation' do
  it 'reads back the exact description declared on a complex type' do
    expect(ComplexTypeDescriptionValidationExample::Address.description).to eq('A postal address')
  end

  it 'treats omitted description as no description on a complex type' do
    klass = Class.new(OdataDuty::ComplexType)
    expect(klass.description).to be_nil
  end

  it 'treats description nil the same as omitted on a complex type' do
    klass = Class.new(OdataDuty::ComplexType) do
      description nil
    end
    expect(klass.description).to be_nil
  end

  it 'raises InvalidDescriptionError naming the type for an empty string' do
    expect do
      class InvalidDescriptionAddressComplexType < OdataDuty::ComplexType
        description ''
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'InvalidDescriptionAddress: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      class WhitespaceDescriptionAddressComplexType < OdataDuty::ComplexType
        description '   '
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'WhitespaceDescriptionAddress: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      class SymbolDescriptionAddressComplexType < OdataDuty::ComplexType
        description :home
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'SymbolDescriptionAddress: description must be a non-empty string')
  end
end

module EntityTypeDescriptionValidationExample
  class Person < OdataDuty::EntityType
    description 'People present at the event'
    property_ref 'id', String
  end

  class Undescribed < OdataDuty::EntityType
    property_ref 'id', String
  end
end

RSpec.describe OdataDuty::EntityType, 'type-level description validation' do
  it 'reads back the exact description declared on an entity type, inherited from ComplexType' do
    expect(EntityTypeDescriptionValidationExample::Person.description)
      .to eq('People present at the event')
  end

  it 'treats omitted description as no description on an entity type' do
    expect(EntityTypeDescriptionValidationExample::Undescribed.description).to be_nil
  end

  it 'raises InvalidDescriptionError naming the entity type for an empty string' do
    expect do
      class InvalidDescriptionPersonEntity < OdataDuty::EntityType
        description ''
        property_ref 'id', String
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'InvalidDescriptionPerson: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      class WhitespaceDescriptionPersonEntity < OdataDuty::EntityType
        description '   '
        property_ref 'id', String
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'WhitespaceDescriptionPerson: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      class SymbolDescriptionPersonEntity < OdataDuty::EntityType
        description :people
        property_ref 'id', String
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'SymbolDescriptionPerson: description must be a non-empty string')
  end
end

module ComplexAndEntityTypeDescriptionMetadataExample
  class AddressComplexType < OdataDuty::ComplexType
    description 'A postal address'
    property 'street', String
  end

  class PersonEntity < OdataDuty::EntityType
    description 'People present at the event'
    property_ref 'id', String
    property 'home', AddressComplexType, nullable: true
  end

  class UndescribedAddressComplexType < OdataDuty::ComplexType
    property 'value', String
  end

  class UndescribedPersonEntity < OdataDuty::EntityType
    property_ref 'id', String
    property 'address', UndescribedAddressComplexType, nullable: true
  end

  class PeopleSet < OdataDuty::EntitySet
    entity_type PersonEntity

    def collection
      []
    end
  end

  class UndescribedPeopleSet < OdataDuty::EntitySet
    entity_type UndescribedPersonEntity

    def collection
      []
    end
  end

  class Schema < OdataDuty::Schema
    namespace 'DescribedTypesSpace'
    base_url 'http://localhost:3000/api'
    entity_sets [PeopleSet, UndescribedPeopleSet]
  end
end

RSpec.describe OdataDuty::ComplexType, '$metadata rendering of type-level description' do
  let(:xml) { ComplexAndEntityTypeDescriptionMetadataExample::Schema.metadata_xml }

  it 'renders the Core Description annotation as the first child of ComplexType' do
    complex_type_index = xml.index('<ComplexType Name="Address">')
    description_index = xml.index(
      '<Annotation Term="Org.OData.Core.V1.Description" String="A postal address" />'
    )
    property_index = xml.index('<Property Name="street"', complex_type_index)
    expect(complex_type_index).to be < description_index
    expect(description_index).to be < property_index
  end

  it 'omits the annotation entirely for a complex type without a description' do
    undescribed_start = xml.index('<ComplexType Name="UndescribedAddress">')
    undescribed_chunk = xml[undescribed_start...(undescribed_start + 300)]
    expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
  end
end

RSpec.describe OdataDuty::EntityType, '$metadata rendering of type-level description' do
  let(:xml) { ComplexAndEntityTypeDescriptionMetadataExample::Schema.metadata_xml }

  it 'renders the Core Description annotation as the first child of EntityType, before Key' do
    entity_type_index = xml.index('<EntityType Name="Person">')
    description_index = xml.index(
      '<Annotation Term="Org.OData.Core.V1.Description" ' \
      'String="People present at the event" />'
    )
    key_index = xml.index('<Key>', entity_type_index)
    expect(entity_type_index).to be < description_index
    expect(description_index).to be < key_index
  end

  it 'omits the annotation entirely for an entity type without a description' do
    undescribed_start = xml.index('<EntityType Name="UndescribedPerson">')
    undescribed_chunk = xml[undescribed_start...(undescribed_start + 300)]
    expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
  end
end
