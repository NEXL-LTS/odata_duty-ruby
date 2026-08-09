require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::ComplexType, 'type-level description validation' do
    def build_complex_type_with_description(description)
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_complex_type(name: 'Address', description: description) do |c|
          c.property 'street', String
        end
      end
      schema.types.fetch('Address')
    end

    it 'raises InvalidDescriptionError naming the type for an empty string' do
      expect { build_complex_type_with_description('') }
        .to raise_error(InvalidDescriptionError,
                        'Address: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_complex_type_with_description('   ') }
        .to raise_error(InvalidDescriptionError,
                        'Address: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_complex_type_with_description(123) }
        .to raise_error(InvalidDescriptionError,
                        'Address: description must be a non-empty string')
    end

    it 'raises InvalidNCNamesError for a bad name before validating an invalid description' do
      expect do
        SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_complex_type(name: 'a b', description: '')
        end
      end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
    end
  end

  RSpec.describe SchemaBuilder::EntityType, 'type-level description validation' do
    def build_entity_type_with_description(description)
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_entity_type(name: 'Person', description: description) do |et|
          et.property_ref 'id', String
        end
      end
      schema.types.fetch('Person')
    end

    it 'raises InvalidDescriptionError naming the type for an empty string' do
      expect { build_entity_type_with_description('') }
        .to raise_error(InvalidDescriptionError,
                        'Person: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_entity_type_with_description('   ') }
        .to raise_error(InvalidDescriptionError,
                        'Person: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_entity_type_with_description(123) }
        .to raise_error(InvalidDescriptionError,
                        'Person: description must be a non-empty string')
    end

    it 'raises InvalidNCNamesError for a bad name before validating an invalid description' do
      expect do
        SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_entity_type(name: 'a b', description: '')
        end
      end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
    end
  end
end
