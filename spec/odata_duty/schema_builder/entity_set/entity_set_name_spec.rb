require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can setup property refs' do
    describe 'name' do
      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
            name_entity = s.add_entity_type(name: 'Name') do |et|
              et.property_ref 'id', String
            end

            s.add_entity_set(entity_type: name_entity, resolver: 'RenamedResolver',
                             name: '0')
          end
        end.to raise_error(InvalidNCNamesError, '"0" is not a valid property name')
      end

      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
            name_entity = s.add_entity_type(name: 'Name') do |et|
              et.property_ref 'id', String
            end

            s.add_entity_set(entity_type: name_entity, resolver: 'RenamedResolver',
                             name: 'a b')
          end
        end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
      end
    end
  end
end
