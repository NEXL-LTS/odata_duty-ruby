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

RSpec.describe OdataDuty::EntityType, 'property description validation' do
  it 'accepts a description string' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: 'First name or full name'
      end
    end.not_to raise_error
  end

  it 'treats omitted description as no description' do
    klass = Class.new(OdataDuty::EntityType) do
      property 'name', String
    end
    expect(klass.properties.last.description).to be_nil
  end

  it 'treats description: nil the same as omitted' do
    klass = Class.new(OdataDuty::EntityType) do
      property 'name', String, description: nil
    end
    expect(klass.properties.last.description).to be_nil
  end

  it 'stores the resolved description on the property' do
    klass = Class.new(OdataDuty::EntityType) do
      property 'name', String, description: 'First name or full name'
    end
    expect(klass.properties.last.description).to eq('First name or full name')
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
    klass = Class.new(OdataDuty::EntityType) do
      property 'name', String, description: DescriptionLikeObject.new('Coerced description')
    end
    description = klass.properties.last.description
    expect(description).to eq('Coerced description')
    expect(description).to be_a(String)
  end

  it 'raises InvalidDescriptionError when the to_str-coercible value is blank' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'name', String, description: DescriptionLikeObject.new('   ')
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'name: description must be a non-empty string')
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
