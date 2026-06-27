require 'spec_helper'

class UpdateScalarsTestResolver < OdataDuty::SetResolver
  def update(id, input)
    OpenStruct.new(id: id, string: input.string, number: input.number)
  end
end

class UpdateIntegerTestResolver < OdataDuty::SetResolver
  def update(id, input)
    return nil unless id == 1

    OpenStruct.new(id: id, string: input.string)
  end
end

class DoesNotSupportUpdateResolver < OdataDuty::SetResolver
end

class UpdateRaisesTestResolver < OdataDuty::SetResolver
  def update(_id, _input)
    nil.genuinely_undefined_method_inside_update
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can update' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        string_entity = s.add_entity_type(name: 'UpdateScalarsTestEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'string', String
          et.property 'number', Integer
        end
        integer_entity = s.add_entity_type(name: 'UpdateIntegerTestEntity') do |et|
          et.property_ref 'id', Integer, computed: false
          et.property 'string', String
        end

        s.add_entity_set(name: 'UpdateScalarsTest', entity_type: string_entity,
                         resolver: 'UpdateScalarsTestResolver')
        s.add_entity_set(name: 'UpdateIntegerTest', entity_type: integer_entity,
                         resolver: 'UpdateIntegerTestResolver')
        s.add_entity_set(name: 'DoesNotSupportUpdate', entity_type: string_entity,
                         resolver: 'DoesNotSupportUpdateResolver')
        s.add_entity_set(name: 'UpdateRaisesTest', entity_type: string_entity,
                         resolver: 'UpdateRaisesTestResolver')
      end
    end

    describe '#update' do
      let(:query_options) { { 'string' => 'Alice Updated' } }
      let(:response) do
        json_string = schema.update("UpdateScalarsTest('1')", context: Context.new,
                                                              query_options: query_options)
        Oj.load(json_string)
      end

      it 'returns the updated entity with individual @odata.context' do
        expect(response).to eq(
          '@odata.context' => 'https://localhost/$metadata#UpdateScalarsTest/$entity',
          '@odata.id' => 'https://localhost/UpdateScalarsTest(\'1\')',
          'id' => '1',
          'string' => 'Alice Updated',
          'number' => nil
        )
      end

      it 'reads omitted fields as nil' do
        query_options.delete('string')
        expect(response).to include('string' => nil)
      end

      it 'coerces the integer key to Integer' do
        json_string = schema.update('UpdateIntegerTest(1)', context: Context.new,
                                                            query_options: { 'string' => 'x' })
        expect(Oj.load(json_string)).to include('id' => 1, 'string' => 'x')
      end

      context 'body value cannot be coerced' do
        it do
          query_options['number'] = 'not-a-number'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end

      context 'key does not exist' do
        it do
          expect do
            schema.update('UpdateIntegerTest(999)', context: Context.new, query_options: {})
          end.to raise_error(OdataDuty::ResourceNotFoundError)
        end
      end

      context 'invalid key in url' do
        it do
          expect do
            schema.update('UpdateIntegerTest(abc)', context: Context.new, query_options: {})
          end.to raise_error(OdataDuty::InvalidPropertyReferenceValue)
        end
      end

      context 'does not support update' do
        it do
          expect do
            schema.update("DoesNotSupportUpdate('1')", context: Context.new, query_options: {})
          end.to raise_error(OdataDuty::NoImplementationError)
        end
      end

      context 'genuine NoMethodError inside update' do
        it 'is not masked as NoImplementationError' do
          expect do
            schema.update("UpdateRaisesTest('1')", context: Context.new, query_options: {})
          end.to raise_error(NoMethodError, /genuinely_undefined_method_inside_update/)
        end
      end
    end
  end
end
