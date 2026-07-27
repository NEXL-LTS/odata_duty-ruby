require 'spec_helper'

class EmptyEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'another', String
end

class UntypedPropertyEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'untyped'
end

class UntypedPropertySet < OdataDuty::EntitySet
  entity_type UntypedPropertyEntity

  def collection
    []
  end
end

class UntypedPropertySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UntypedPropertySet]
end

module OdataDuty
  RSpec.describe EntitySet, 'Can setup property' do
    subject(:schema) { PropertyRefsTestSchema }

    describe 'property names must be unique' do
      it 'cannot have same name as property_ref' do
        expect do
          EmptyEntity.property 'id', String
        end.to raise_error(PropertyAlreadyDefinedError, 'id is already defined')
      end

      it 'cannot have same name as another property' do
        expect do
          EmptyEntity.property 'another', String
        end.to raise_error(PropertyAlreadyDefinedError, 'another is already defined')
      end
    end

    describe 'property type resolution' do
      it 'defaults to Edm.String when no type is given' do
        properties = UntypedPropertySchema.metadata_xml
        doc = parse_xml_from_string(properties)
        untyped = entity_types_from_doc(doc)['UntypedProperty'][:properties]
        expect(untyped).to include(name: 'untyped', type: 'Edm.String', nullable: 'true')
      end

      it 'raises for an unsupported property type' do
        expect do
          Class.new(EntityType) { property 'bad', nil }
        end.to raise_error(RuntimeError, /Invalid type nil for bad/)
      end
    end

    describe 'property names must be valid NCNames' do
      it 'rejects a name whose first character is a digit' do
        expect do
          Class.new(EntityType) { property '1bad', String }
        end.to raise_error(InvalidNCNamesError, '"1bad" is not a valid property name')
      end

      it 'rejects a name containing a hyphen' do
        expect do
          Class.new(EntityType) { property 'bad-name', String }
        end.to raise_error(InvalidNCNamesError, '"bad-name" is not a valid property name')
      end

      it 'rejects an empty name' do
        expect do
          Class.new(EntityType) { property '', String }
        end.to raise_error(InvalidNCNamesError, '"" is not a valid property name')
      end

      it 'accepts a name with a digit after the first letter' do
        expect do
          Class.new(EntityType) { property 'a1', String }
        end.not_to raise_error
      end

      it 'accepts a name whose first character is an underscore' do
        expect do
          Class.new(EntityType) { property '_private', String }
        end.not_to raise_error
      end

      it 'accepts a name whose first character is a unicode letter' do
        expect do
          Class.new(EntityType) { property 'élan', String }
        end.not_to raise_error
      end

      it 'accepts a Symbol name, matching String behavior' do
        expect do
          Class.new(EntityType) { property :id, String }
        end.not_to raise_error
      end

      it 'rejects an invalid Symbol name with InvalidNCNamesError, not NoMethodError' do
        expect do
          Class.new(EntityType) { property :'bad-name', String }
        end.to raise_error(InvalidNCNamesError, '"bad-name" is not a valid property name')
      end
    end
  end
end
