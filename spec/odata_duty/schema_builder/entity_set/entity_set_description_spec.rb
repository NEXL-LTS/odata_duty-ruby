require 'spec_helper'

class EntitySetDescriptionPeopleResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'entity-set-level description validation' do
    def build_with_description(description)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'DescPerson') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'EntitySetDescriptionPeopleResolver',
                         description: description)
      end
    end

    it 'reads back the exact description assigned on the entity set' do
      schema = build_with_description('Attendees checked in at the front desk')
      entity_set = schema.entity_sets.first
      expect(entity_set.description).to eq('Attendees checked in at the front desk')
    end

    it 'treats omitted description as no description' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '') do |s|
        entity = s.add_entity_type(name: 'DescPerson') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'EntitySetDescriptionPeopleResolver')
      end
      expect(schema.entity_sets.first.description).to be_nil
    end

    it 'treats description: nil the same as omitted' do
      expect(build_with_description(nil).entity_sets.first.description).to be_nil
    end

    it 'raises InvalidDescriptionError naming the set for an empty string' do
      expect { build_with_description('') }
        .to raise_error(InvalidDescriptionError, 'People: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_with_description('   ') }
        .to raise_error(InvalidDescriptionError, 'People: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_with_description(123) }
        .to raise_error(InvalidDescriptionError, 'People: description must be a non-empty string')
    end

    it 'raises InvalidNCNamesError for a bad name before InvalidDescriptionError for a ' \
       'bad description' do
      expect do
        SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
          entity = s.add_entity_type(name: 'DescPerson') { |et| et.property_ref 'id', String }
          s.add_entity_set(name: 'a b', entity_type: entity,
                           resolver: 'EntitySetDescriptionPeopleResolver',
                           description: '')
        end
      end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
    end
  end
end
