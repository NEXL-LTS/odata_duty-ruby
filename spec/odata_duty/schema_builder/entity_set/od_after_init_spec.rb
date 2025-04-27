require 'spec_helper'

class BaseArgsTesterResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1', arg: @arg)]
  end

  def individual(id)
    collection.find { |x| x.id == id.to_str }
  end
end

class NoInitArgsResolver < BaseArgsTesterResolver
  def od_after_init; end
end

class OptionalInitKwArgResolver < BaseArgsTesterResolver
  def od_after_init(arg: 'default')
    @arg = arg
  end
end

class OptionalInitPosArgResolver < BaseArgsTesterResolver
  def od_after_init(arg = 'default')
    @arg = arg
  end
end

class InitErrorsArgsResolver < BaseArgsTesterResolver
  def od_after_init(arg)
    @arg = arg.to_s('force', 'argument', 'error')
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can pass additional args to od_after_init' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        entity_type = s.add_entity_type(name: 'InitArgTest') do |et|
          et.property_ref 'id', String
          et.property 'arg', String
        end

        s.add_entity_set(name: 'NoInitArgs', entity_type: entity_type,
                         resolver: 'NoInitArgsResolver')
        s.add_entity_set(name: 'OptionalInitKwArgDefault', entity_type: entity_type,
                         resolver: 'OptionalInitKwArgResolver')
        s.add_entity_set(name: 'OptionalInitKwArgChanged', entity_type: entity_type,
                         resolver: 'OptionalInitKwArgResolver',
                         init_args: { arg: 'changed' })
        s.add_entity_set(name: 'OptionalInitPosArgDefault', entity_type: entity_type,
                         resolver: 'OptionalInitPosArgResolver')
        s.add_entity_set(name: 'OptionalInitPosArgChanged', entity_type: entity_type,
                         resolver: 'OptionalInitPosArgResolver',
                         init_args: 'changed')
        s.add_entity_set(name: 'OptionalInitPosArgArrayChanged', entity_type: entity_type,
                         resolver: 'OptionalInitPosArgResolver',
                         init_args: ['array_changed'])
      end
    end

    describe '#oas_2' do
      let(:json) { OAS2.build_json(schema, context: Context.new) }

      it do
        expect(json.keys)
          .to eq(%w[swagger info host schemes basePath paths definitions])
      end

      context 'with a entity set that requires args' do
        it 'raises error InitArgsMismatchError when none given' do
          schema.add_entity_set(name: 'InitErrors', entity_type: 'InitArgTest', resolver: 'InitErrorsArgsResolver')
          expect { json }.to raise_error(
            OdataDuty::InitArgsMismatchError, 
            "wrong number of arguments (given 0, expected 1)"
          )
        end

        it 'raises error ArgumentError when error inside of resolver' do
          schema.add_entity_set(name: 'InsideError', entity_type: 'InitArgTest', resolver: 'InitErrorsArgsResolver', init_args: 'given')
          expect { json }.to raise_error(
            ArgumentError,
            "wrong number of arguments (given 3, expected 0)"
          )
        end
      end
    end

    describe '#execute' do
      describe 'collection' do
        let(:json_string) { schema.execute(path, context: Context.new) }
        let(:response) { Oj.load(json_string) }

        context 'when no init args' do
          let(:path) { 'NoInitArgs' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#NoInitArgs',
                'value' => [
                  '@odata.id' => 'https://localhost/NoInitArgs(\'1\')',
                  'id' => '1',
                  'arg' => nil
                ]
              }
            )
          end
        end

        context 'when optional kwargs not used' do
          let(:path) { 'OptionalInitKwArgDefault' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitKwArgDefault',
                'value' => [
                  '@odata.id' => 'https://localhost/OptionalInitKwArgDefault(\'1\')',
                  'id' => '1',
                  'arg' => 'default'
                ]
              }
            )
          end
        end

        context 'when optional kwargs used' do
          let(:path) { 'OptionalInitKwArgChanged' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitKwArgChanged',
                'value' => [
                  '@odata.id' => 'https://localhost/OptionalInitKwArgChanged(\'1\')',
                  'id' => '1',
                  'arg' => 'changed'
                ]
              }
            )
          end
        end

        context 'when optional positional args not used' do
          let(:path) { 'OptionalInitPosArgDefault' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgDefault',
                'value' => [
                  '@odata.id' => 'https://localhost/OptionalInitPosArgDefault(\'1\')',
                  'id' => '1',
                  'arg' => 'default'
                ]
              }
            )
          end
        end

        context 'when optional positional args used' do
          let(:path) { 'OptionalInitPosArgChanged' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgChanged',
                'value' => [
                  '@odata.id' => 'https://localhost/OptionalInitPosArgChanged(\'1\')',
                  'id' => '1',
                  'arg' => 'changed'
                ]
              }
            )
          end
        end

        context 'when optional positional args used with array' do
          let(:path) { 'OptionalInitPosArgArrayChanged' }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgArrayChanged',
                'value' => [
                  '@odata.id' => 'https://localhost/OptionalInitPosArgArrayChanged(\'1\')',
                  'id' => '1',
                  'arg' => 'array_changed'
                ]
              }
            )
          end
        end
      end

      describe 'individual' do
        let(:json_string) { schema.execute(path, context: Context.new) }
        let(:response) { Oj.load(json_string) }

        context 'with no init args' do
          let(:path) { "NoInitArgs('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#NoInitArgs/$entity',
                '@odata.id' => 'https://localhost/NoInitArgs(\'1\')',
                'id' => '1',
                'arg' => nil
              }
            )
          end
        end

        context 'when optional kwargs not used' do
          let(:path) { "OptionalInitKwArgDefault('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitKwArgDefault/$entity',
                '@odata.id' => 'https://localhost/OptionalInitKwArgDefault(\'1\')',
                'id' => '1',
                'arg' => 'default'
              }
            )
          end
        end

        context 'when optional kwargs used' do
          let(:path) { "OptionalInitKwArgChanged('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitKwArgChanged/$entity',
                '@odata.id' => 'https://localhost/OptionalInitKwArgChanged(\'1\')',
                'id' => '1',
                'arg' => 'changed'
              }
            )
          end
        end

        context 'when optional positional args not used' do
          let(:path) { "OptionalInitPosArgDefault('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgDefault/$entity',
                '@odata.id' => 'https://localhost/OptionalInitPosArgDefault(\'1\')',
                'id' => '1',
                'arg' => 'default'
              }
            )
          end
        end

        context 'when optional positional args used' do
          let(:path) { "OptionalInitPosArgChanged('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgChanged/$entity',
                '@odata.id' => 'https://localhost/OptionalInitPosArgChanged(\'1\')',
                'id' => '1',
                'arg' => 'changed'
              }
            )
          end
        end

        context 'when optional positional args used with array' do
          let(:path) { "OptionalInitPosArgArrayChanged('1')" }

          it do
            expect(response).to eq(
              {
                '@odata.context' => 'https://localhost/$metadata#OptionalInitPosArgArrayChanged/$entity',
                '@odata.id' => 'https://localhost/OptionalInitPosArgArrayChanged(\'1\')',
                'id' => '1',
                'arg' => 'array_changed'
              }
            )
          end
        end
      end
    end
  end
end
