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

    it 'reads back the exact description declared on a complex type' do
      complex_type = build_complex_type_with_description('A postal address')
      expect(complex_type.description).to eq('A postal address')
    end

    it 'treats omitted description as no description on a complex type' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_complex_type(name: 'Undescribed') { |c| c.property 'street', String }
      end
      expect(schema.types.fetch('Undescribed').description).to be_nil
    end

    it 'treats description: nil the same as omitted on a complex type' do
      expect(build_complex_type_with_description(nil).description).to be_nil
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

    it 'renders the OAS2 definition with the description alongside type and properties' do
      complex_type = build_complex_type_with_description('A postal address')
      expect(complex_type.to_oas2).to eq(
        'type' => 'object',
        'description' => 'A postal address',
        'properties' => { 'street' => { 'type' => 'string', 'x-nullable' => true } }
      )
    end

    it 'renders the OAS2 definition without a description key when there is none' do
      complex_type = build_complex_type_with_description(nil)
      expect(complex_type.to_oas2).to eq(
        'type' => 'object',
        'properties' => { 'street' => { 'type' => 'string', 'x-nullable' => true } }
      )
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

    it 'reads back the exact description declared on an entity type, via DataType' do
      entity_type = build_entity_type_with_description('People present at the event')
      expect(entity_type.description).to eq('People present at the event')
    end

    it 'treats omitted description as no description on an entity type' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_entity_type(name: 'Undescribed') { |et| et.property_ref 'id', String }
      end
      expect(schema.types.fetch('Undescribed').description).to be_nil
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
