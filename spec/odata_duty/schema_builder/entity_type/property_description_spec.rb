require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'property description validation' do
    def build_with_description(description)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_entity_type(name: 'DescribedBuilderProperty') do |et|
          et.property_ref 'id', String
          et.property 'name', String, description: description
        end
      end
    end

    it 'accepts a description string' do
      expect { build_with_description('First name or full name') }.not_to raise_error
    end

    it 'treats omitted description as no description' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_entity_type(name: 'UndescribedBuilderProperty') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end
      end
      entity_type = schema.entity_types.find { |et| et.name == 'UndescribedBuilderProperty' }
      property = entity_type.properties.find { |p| p.name == :name }
      expect(property.description).to be_nil
    end

    it 'treats description: nil the same as omitted' do
      expect { build_with_description(nil) }.not_to raise_error
    end

    it 'raises InvalidDescriptionError naming the property for an empty string' do
      expect { build_with_description('') }
        .to raise_error(InvalidDescriptionError, 'name: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_with_description('   ') }
        .to raise_error(InvalidDescriptionError, 'name: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_with_description(123) }
        .to raise_error(InvalidDescriptionError, 'name: description must be a non-empty string')
    end

    it 'raises InvalidNCNamesError for a bad name before validating an invalid description' do
      expect do
        SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_entity_type(name: 'BadNameDescribedProperty') do |et|
            et.property_ref 'id', String
            et.property 'a b', String, description: ''
          end
        end
      end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
    end
  end
end
