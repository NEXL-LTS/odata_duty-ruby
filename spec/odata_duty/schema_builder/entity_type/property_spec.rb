require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can setup property refs' do
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
    end
  end
end
