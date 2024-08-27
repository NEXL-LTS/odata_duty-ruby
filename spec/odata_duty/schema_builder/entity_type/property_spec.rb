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
    end
  end
end
