require 'spec_helper'

# A minimal to_str-coercible value, distinct from String, to prove the description is coerced
# via `to_str` rather than stored/checked as the original object.
class DescriptionLikeObject
  def initialize(value)
    @value = value
  end

  def to_str
    @value
  end
end

# Returns a different value on each `to_str` call, to prove validation and storage both use a
# single captured coercion rather than two independent calls that could observe different values.
class UnstableDescriptionObject
  def initialize(*values)
    @values = values
  end

  def to_str
    @values.shift
  end
end

# Responds to `match?` but is not a String, to prove a `to_str` result is validated by class,
# not merely by responding to the methods the validator happens to call.
class MatchableNonString
  def match?(*)
    true
  end
end

# A String subclass, distinct from String itself, to prove the validator accepts subclasses
# (e.g. ActiveSupport::SafeBuffer) rather than requiring an exact String instance.
class DescriptionStringSubclass < String; end

RSpec.describe OdataDuty::EntityType, 'property description validation' do
  # Render a property named `name` (with the given description) into $metadata and
  # return just that property's <Property> fragment, so the Core.Description
  # annotation (or its absence) is asserted on public output, not an internal reader.
  def name_property_xml(**property_kwargs)
    entity_type = Class.new(OdataDuty::EntityType) do
      property_ref 'id', String
      property 'name', String, **property_kwargs
    end
    entity_set = Class.new(OdataDuty::EntitySet) { entity_type entity_type }
    schema = Class.new(OdataDuty::Schema) do
      namespace 'PropertyDescriptionSpace'
      entity_sets [entity_set]
    end
    schema.metadata_xml.split('<Property Name="name"')[1].split('<Property ')[0]
  end

  DESCRIPTION_TERM = 'Term="Org.OData.Core.V1.Description"'.freeze

  it 'accepts a description string' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: 'First name or full name'
      end
    end.not_to raise_error
  end

  it 'treats omitted description as no description' do
    expect(name_property_xml).not_to include(DESCRIPTION_TERM)
  end

  it 'treats description: nil the same as omitted' do
    expect(name_property_xml(description: nil)).not_to include(DESCRIPTION_TERM)
  end

  it 'stores the resolved description on the property' do
    expect(name_property_xml(description: 'First name or full name'))
      .to include("#{DESCRIPTION_TERM} String=\"First name or full name\"")
  end

  it 'raises InvalidDescriptionError naming the property for an empty string' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: ''
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: '   '
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: :people
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
  end

  it 'is an ArgumentError' do
    expect(OdataDuty::InvalidDescriptionError.ancestors).to include(ArgumentError)
  end

  it 'raises InvalidNCNamesError for a bad name before validating an invalid description' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'a b', String, description: ''
      end
    end.to raise_error(OdataDuty::InvalidNCNamesError, '"a b" is not a valid property name')
  end

  it 'accepts a to_str-coercible non-String value and stores the coerced String' do
    xml = name_property_xml(description: DescriptionLikeObject.new('Coerced description'))
    expect(xml).to include("#{DESCRIPTION_TERM} String=\"Coerced description\"")
  end

  it 'raises InvalidDescriptionError when the to_str-coercible value is blank' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: DescriptionLikeObject.new('   ')
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
  end

  it 'validates and stores the same single to_str call, not two independent calls' do
    xml = name_property_xml(description: UnstableDescriptionObject.new('Valid description', ''))
    expect(xml).to include("#{DESCRIPTION_TERM} String=\"Valid description\"")
  end

  it 'raises InvalidDescriptionError when to_str coerces to a non-String value' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: DescriptionLikeObject.new(MatchableNonString.new)
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
  end

  it 'accepts a to_str result that is a String subclass' do
    xml = name_property_xml(
      description: DescriptionLikeObject.new(DescriptionStringSubclass.new('Subclass'))
    )
    expect(xml).to include("#{DESCRIPTION_TERM} String=\"Subclass\"")
  end

  it 'still raises PropertyAlreadyDefinedError for a duplicate name regardless of description' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: 'First'
        property 'name', String, description: 'Second'
      end
    end.to raise_error(OdataDuty::PropertyAlreadyDefinedError, 'name is already defined')
  end
end
