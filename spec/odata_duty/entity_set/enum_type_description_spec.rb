require 'spec_helper'

RSpec.describe OdataDuty::EnumType, 'type-level description validation' do
  it 'reads back the exact description declared on an enum type' do
    klass = Class.new(OdataDuty::EnumType) do
      description 'Gender as recorded at registration'
    end
    expect(klass.description).to eq('Gender as recorded at registration')
  end

  it 'treats omitted description as no description on an enum type' do
    klass = Class.new(OdataDuty::EnumType)
    expect(klass.description).to be_nil
  end

  it 'treats description nil the same as omitted on an enum type' do
    klass = Class.new(OdataDuty::EnumType) do
      description nil
    end
    expect(klass.description).to be_nil
  end

  it 'raises InvalidDescriptionError naming the type for an empty string' do
    expect do
      class InvalidDescriptionGenderEnumType < OdataDuty::EnumType
        description ''
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'InvalidDescriptionGender: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      class WhitespaceDescriptionGenderEnumType < OdataDuty::EnumType
        description '   '
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'WhitespaceDescriptionGender: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      class SymbolDescriptionGenderEnumType < OdataDuty::EnumType
        description :gender
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'SymbolDescriptionGender: description must be a non-empty string')
  end
end

module EnumTypeDescriptionMetadataExample
  class GenderEnumType < OdataDuty::EnumType
    description 'Gender as recorded at registration'
    member 'Male', description: 'Recorded as male'
    member 'Female', description: 'Recorded as female'
  end

  class UndescribedEnumType < OdataDuty::EnumType
    member 'One'
  end

  class PersonEntity < OdataDuty::EntityType
    property_ref 'id', String
    property 'gender', GenderEnumType, nullable: true
    property 'other', UndescribedEnumType, nullable: true
  end

  class PeopleSet < OdataDuty::EntitySet
    entity_type PersonEntity

    def collection
      []
    end
  end

  class Schema < OdataDuty::Schema
    namespace 'DescribedEnumSpace'
    base_url 'http://localhost:3000/api'
    entity_sets [PeopleSet]
  end
end

RSpec.describe OdataDuty::EnumType, '$metadata rendering of type-level description' do
  let(:xml) { EnumTypeDescriptionMetadataExample::Schema.metadata_xml }

  it 'renders the Core Description annotation as the first child of EnumType' do
    enum_type_index = xml.index('<EnumType Name="Gender">')
    description_index = xml.index(
      '<Annotation Term="Org.OData.Core.V1.Description" ' \
      'String="Gender as recorded at registration" />'
    )
    member_index = xml.index('<Member Name="Male"', enum_type_index)
    expect(enum_type_index).to be < description_index
    expect(description_index).to be < member_index
  end

  it 'omits the annotation entirely for an enum type without a description' do
    undescribed_start = xml.index('<EnumType Name="Undescribed">')
    undescribed_chunk = xml[undescribed_start...(undescribed_start + 200)]
    expect(undescribed_chunk).not_to include('Org.OData.Core.V1.Description')
  end

  it 'renders a Description annotation as a child of a described Member' do
    male_index = xml.index('<Member Name="Male">')
    description_index = xml.index(
      '<Annotation Term="Org.OData.Core.V1.Description" String="Recorded as male" />'
    )
    female_index = xml.index('<Member Name="Female">')
    expect(male_index).to be < description_index
    expect(description_index).to be < female_index
  end

  it 'keeps an undescribed member self-closed' do
    expect(xml).to include('<Member Name="One" />')
  end
end
