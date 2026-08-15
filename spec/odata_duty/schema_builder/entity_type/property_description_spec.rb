require 'spec_helper'

class PropertyDescriptionCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

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
        entity = s.add_entity_type(name: 'UndescribedBuilderProperty') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end
        s.add_entity_set(name: 'UndescribedBuilderProperties', entity_type: entity,
                         resolver: 'PropertyDescriptionCollectionResolver')
      end
      property_xml = schema.metadata_xml.split('<Property Name="name"')[1].split('<Property ')[0]
      expect(property_xml).not_to include('Term="Org.OData.Core.V1.Description"')
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
