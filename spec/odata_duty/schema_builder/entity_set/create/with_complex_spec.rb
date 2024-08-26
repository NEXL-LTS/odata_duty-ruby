require 'spec_helper'

class CreateComplexTestResolver < OdataDuty::SetResolver
  def create(params)
    return params unless params.complex

    params.id
    params.complex.tap do |complex|
      %i[string string_list number number_list date date_list datetime datetime_list bool
         bool_list].each do |key|
        complex.public_send(key)
      end
    end
    params
  end
end

class InvalidPropertyTestResolver < OdataDuty::SetResolver
  def create(params)
    params.not_exist
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can create' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        complex_type = s.add_complex_type(name: 'CreateTestComplex') do |et|
          et.property 'string', String
          et.property 'string_list', [String]
          et.property 'number', Integer
          et.property 'number_list', [Integer]
          et.property 'date', Date
          et.property 'date_list', [Date]
          et.property 'datetime', DateTime
          et.property 'datetime_list', [DateTime]
          et.property 'bool', TrueClass
          et.property 'bool_list', [TrueClass]
        end

        collection_entity = s.add_entity_type(name: 'CreateComplexTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'complex', complex_type
        end

        s.add_entity_set(name: 'CreateComplexTest', entity_type: collection_entity,
                         resolver: 'CreateComplexTestResolver')
        s.add_entity_set(name: 'InvalidPropertyTest', entity_type: collection_entity,
                         resolver: 'InvalidPropertyTestResolver')
      end
    end

    describe '#create' do
      let(:query_options) { { 'id' => '1' } }
      let(:response) do
        json_string = schema.create('CreateComplexTest', context: Context.new,
                                                         query_options: query_options)
        Oj.load(json_string)
      end

      it do
        expect(response).to eq(
          '@odata.context' => '$metadata#CreateComplexTest/$entity',
          '@odata.id' => 'CreateComplexTest(\'1\')',
          'id' => '1',
          'complex' => nil
        )
      end

      context 'with complex' do
        let(:complex_options) { {} }
        let(:query_options) { { 'id' => '1', 'complex' => complex_options } }

        it 'returns complex if empty hash' do
          expect(response).to include('complex' => { 'string' => nil,
                                                     'string_list' => nil,
                                                     'number' => nil,
                                                     'number_list' => nil,
                                                     'date' => nil,
                                                     'date_list' => nil,
                                                     'datetime' => nil,
                                                     'datetime_list' => nil,
                                                     'bool' => nil,
                                                     'bool_list' => nil })
        end

        describe 'string' do
          it do
            complex_options['string'] = 'str'
            expect(response['complex']).to include('string' => 'str')
          end

          context 'is not a string value' do
            it do
              complex_options['string'] = 1
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'string_list' do
          it do
            complex_options['string_list'] = %w[str1 str2]
            expect(response['complex']).to include('string_list' => %w[str1 str2])
          end

          context 'is not a string list' do
            it do
              complex_options['string_list'] = 'str'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'number' do
          it do
            complex_options['number'] = 1
            expect(response['complex']).to include('number' => 1)
          end

          context 'is not a number value' do
            it do
              complex_options['number'] = 'str'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'number_list' do
          it do
            complex_options['number_list'] = [1, 2]
            expect(response['complex']).to include('number_list' => [1, 2])
          end

          context 'is not a number list' do
            it do
              complex_options['number_list'] = 1
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'date' do
          it do
            complex_options['date'] = '2021-01-01'
            expect(response['complex']).to include('date' => Date.new(2021, 1, 1).iso8601)
          end

          context 'is not a date value' do
            it do
              complex_options['date'] = true
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end

          context 'is not a valid date' do
            it do
              complex_options['date'] = '2021-01-32'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'date_list' do
          it do
            complex_options['date_list'] = %w[2021-01-01 2021-01-02]
            expect(response['complex']).to include('date_list' => %w[2021-01-01 2021-01-02])
          end

          context 'is not a date list' do
            it do
              complex_options['date_list'] = '2021-01-01'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end

          context 'is not a valid date' do
            it do
              complex_options['date_list'] = %w[2021-01-01 2021-01-32]
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'datetime' do
          it do
            complex_options['datetime'] = '2021-01-01T00:00:00Z'
            expect(response['complex']).to include('datetime' => DateTime.new(2021, 1, 1, 0, 0,
                                                                              0).iso8601)
          end

          context 'is not a datetime value' do
            it do
              complex_options['datetime'] = true
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end

          context 'is not a valid datetime' do
            it do
              complex_options['datetime'] = '2021-01-01T99:99:99'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'datetime_list' do
          it do
            complex_options['datetime_list'] = %w[2021-01-01T00:00:00Z 2021-01-02T00:00:00Z]
            expect(response['complex']).to include(
              'datetime_list' => %w[2021-01-01T00:00:00+00:00
                                    2021-01-02T00:00:00+00:00]
            )
          end

          context 'is not a datetime list' do
            it do
              complex_options['datetime_list'] = '2021-01-01T00:00:00Z'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end

          context 'is not a valid datetime' do
            it do
              complex_options['datetime_list'] = %w[2021-01-01T00:00:00Z 2021-01-02T99:99:99]
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'bool' do
          it do
            complex_options['bool'] = true
            expect(response['complex']).to include('bool' => true)
          end

          context 'is not a bool value' do
            it do
              complex_options['bool'] = 'bool'
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end

        describe 'bool_list' do
          it do
            complex_options['bool_list'] = [true, false]
            expect(response['complex']).to include('bool_list' => [true, false])
          end

          context 'is not a bool list' do
            it do
              complex_options['bool_list'] = true
              expect { response }.to raise_error(OdataDuty::InvalidType)
            end
          end
        end
      end

      context 'Accessing non existent property' do
        it do
          expect do
            schema.create('InvalidPropertyTest', context: Context.new,
                                                 query_options: { 'id' => '1' })
          end.to raise_error(OdataDuty::NoSuchPropertyError)
        end
      end
    end
  end
end
