require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can setup property refs' do
    describe 'property type resolution' do
      it 'defaults to Edm.String when no type is given' do
        schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_entity_type(name: 'UntypedBuilderProperty') do |et|
            et.property_ref 'id', String
            et.property 'untyped'
          end
        end
        doc = parse_xml_from_string(schema.metadata_xml)
        properties = entity_types_from_doc(doc)['UntypedBuilderProperty'][:properties]
        expect(properties).to include(name: 'untyped', type: 'Edm.String', nullable: 'true')
      end

      it 'raises for an unsupported property type' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'BadBuilderProperty') do |et|
              et.property_ref 'id', String
              et.property 'bad', nil
            end
          end
        end.to raise_error(RuntimeError, /Invalid type nil for bad/)
      end
    end

    describe 'property names must be unique' do
      it 'cannot have same name as property_ref' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'StringRef') do |et|
              et.property_ref 'id', String
              et.property 'id', String
            end
          end
        end.to raise_error(PropertyAlreadyDefinedError, 'id is already defined')
      end

      it 'cannot have same name as another property' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'StringRef') do |et|
              et.property_ref 'id', String
              et.property 'another', String
              et.property 'another', String
            end
          end
        end.to raise_error(PropertyAlreadyDefinedError, 'another is already defined')
      end

      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'StringRef') do |et|
              et.property_ref 'id', String
              et.property '0', String
            end
          end
        end.to raise_error(InvalidNCNamesError, '"0" is not a valid property name')
      end

      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'StringRef') do |et|
              et.property_ref 'id', String
              et.property 'a b', String
            end
          end
        end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
      end

      it 'accepts Symbol property names, matching String behavior' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'SymbolNames') do |et|
              et.property_ref :id, String
              et.property :name, String
            end
          end
        end.not_to raise_error
      end

      it 'rejects an invalid Symbol name with InvalidNCNamesError, not NoMethodError' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'SymbolNames') do |et|
              et.property_ref :id, String
              et.property :'bad-name', String
            end
          end
        end.to raise_error(InvalidNCNamesError, '"bad-name" is not a valid property name')
      end
    end
  end
end
