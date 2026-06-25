require 'spec_helper'

class DeleteScalarsTestEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'string', String
end

class DeleteScalarsTestSet < OdataDuty::EntitySet
  entity_type DeleteScalarsTestEntity

  def delete(id)
    OpenStruct.new(id: id)
  end
end

class DeleteIntegerTestEntity < OdataDuty::EntityType
  property_ref 'id', Integer, computed: false
  property 'string', String
end

class DeleteIntegerTestSet < OdataDuty::EntitySet
  entity_type DeleteIntegerTestEntity

  def delete(id)
    return nil unless id == 1

    true
  end
end

class DoesNotSupportDeleteSet < OdataDuty::EntitySet
  entity_type DeleteScalarsTestEntity
end

class DeleteTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [DeleteScalarsTestSet, DeleteIntegerTestSet, DoesNotSupportDeleteSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can delete' do
  subject(:schema) { DeleteTestSchema }

  describe '#delete' do
    it 'returns no entity payload on success' do
      result = schema.delete("DeleteScalarsTest('1')", context: Context.new, query_options: {})
      expect(Oj.load(result)).not_to include('id')
    end

    it 'coerces the integer key to Integer' do
      expect do
        schema.delete('DeleteIntegerTest(1)', context: Context.new, query_options: {})
      end.not_to raise_error
    end

    context 'key does not exist' do
      it do
        expect do
          schema.delete('DeleteIntegerTest(999)', context: Context.new, query_options: {})
        end.to raise_error(OdataDuty::ResourceNotFoundError)
      end
    end

    context 'invalid key in url' do
      it do
        expect do
          schema.delete('DeleteIntegerTest(abc)', context: Context.new, query_options: {})
        end.to raise_error(OdataDuty::InvalidPropertyReferenceValue)
      end
    end

    context 'does not support delete' do
      it do
        expect do
          schema.delete("DoesNotSupportDelete('1')", context: Context.new, query_options: {})
        end.to raise_error(OdataDuty::NoImplementationError)
      end
    end
  end
end
