require 'spec_helper'

class EmptyEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'another', String
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
  end
end
