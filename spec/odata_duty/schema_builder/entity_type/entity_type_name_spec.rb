require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'Can setup property refs' do
    describe 'name' do
      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: '0')
          end
        end.to raise_error(InvalidNCNamesError, '"0" is not a valid property name')
      end

      it do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'a b')
          end
        end.to raise_error(InvalidNCNamesError, '"a b" is not a valid property name')
      end
    end
  end
end
