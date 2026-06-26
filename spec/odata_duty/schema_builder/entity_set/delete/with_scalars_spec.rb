require 'spec_helper'

class DeleteScalarsTestResolver < OdataDuty::SetResolver
  def delete(id)
    OpenStruct.new(id: id)
  end
end

class DeleteIntegerTestResolver < OdataDuty::SetResolver
  def delete(id)
    return nil unless id == 1

    true
  end
end

class DoesNotSupportDeleteResolver < OdataDuty::SetResolver
end

class DeleteRaisesTestResolver < OdataDuty::SetResolver
  def delete(_id)
    nil.genuinely_undefined_method_inside_delete
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can delete' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        string_entity = s.add_entity_type(name: 'DeleteScalarsTestEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'string', String
        end
        integer_entity = s.add_entity_type(name: 'DeleteIntegerTestEntity') do |et|
          et.property_ref 'id', Integer, computed: false
          et.property 'string', String
        end

        s.add_entity_set(name: 'DeleteScalarsTest', entity_type: string_entity,
                         resolver: 'DeleteScalarsTestResolver')
        s.add_entity_set(name: 'DeleteIntegerTest', entity_type: integer_entity,
                         resolver: 'DeleteIntegerTestResolver')
        s.add_entity_set(name: 'DoesNotSupportDelete', entity_type: string_entity,
                         resolver: 'DoesNotSupportDeleteResolver')
        s.add_entity_set(name: 'DeleteRaisesTest', entity_type: string_entity,
                         resolver: 'DeleteRaisesTestResolver')
      end
    end

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
          end.to raise_error(ResourceNotFoundError)
        end
      end

      context 'invalid key in url' do
        it do
          expect do
            schema.delete('DeleteIntegerTest(abc)', context: Context.new, query_options: {})
          end.to raise_error(InvalidPropertyReferenceValue)
        end
      end

      context 'does not support delete' do
        it do
          expect do
            schema.delete("DoesNotSupportDelete('1')", context: Context.new, query_options: {})
          end.to raise_error(NoImplementationError)
        end
      end

      context 'genuine NoMethodError inside delete' do
        it 'is not masked as NoImplementationError' do
          expect do
            schema.delete("DeleteRaisesTest('1')", context: Context.new, query_options: {})
          end.to raise_error(NoMethodError, /genuinely_undefined_method_inside_delete/)
        end
      end
    end
  end
end
