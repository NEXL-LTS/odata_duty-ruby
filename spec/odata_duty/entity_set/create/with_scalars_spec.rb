require 'spec_helper'

class CreateScalarsTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'string', String
  property 'string_list', [String]
  property 'number', Integer
  property 'number_list', [Integer]
  property 'date', Date
  property 'date_list', [Date]
  property 'datetime', DateTime
  property 'datetime_list', [DateTime]
  property 'bool', TrueClass
  property 'bool_list', [TrueClass]
end

class CreateScalarsTestSet < OdataDuty::EntitySet
  entity_type CreateScalarsTestEntity

  def create(params)
    %i[id string string_list number number_list date date_list datetime datetime_list bool
       bool_list].each do |key|
      params.public_send(key)
    end
    params
  end
end

class DoesNotSupportCreateSet < OdataDuty::EntitySet
  entity_type CreateScalarsTestEntity
end

class CreateTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [CreateScalarsTestSet, DoesNotSupportCreateSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can create' do
  subject(:schema) { CreateTestSchema }

  describe '#create' do
    let(:query_options) { { 'id' => '1' } }
    let(:response) do
      json_string = schema.create('CreateScalarsTest', context: Context.new,
                                                       query_options: query_options)
      Oj.load(json_string)
    end

    it do
      expect(response).to eq(
        '@odata.context' => 'http://localhost:3000/api/$metadata#CreateScalarsTest/$entity',
        '@odata.id' => 'http://localhost:3000/api/CreateScalarsTest(\'1\')',
        'id' => '1',
        'string' => nil,
        'string_list' => nil,
        'number' => nil,
        'number_list' => nil,
        'date' => nil,
        'date_list' => nil,
        'datetime' => nil,
        'datetime_list' => nil,
        'bool' => nil,
        'bool_list' => nil
      )
    end

    describe 'string' do
      it do
        query_options['string'] = 'str'
        expect(response).to include('string' => 'str')
      end

      context 'is not a string value' do
        it do
          query_options['string'] = 1
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'string_list' do
      it do
        query_options['string_list'] = %w[str1 str2]
        expect(response).to include('string_list' => %w[str1 str2])
      end

      context 'is not a string list' do
        it do
          query_options['string_list'] = 'str'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'number' do
      it do
        query_options['number'] = 1
        expect(response).to include('number' => 1)
      end

      context 'is not a number value' do
        it do
          query_options['number'] = 'str'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'number_list' do
      it do
        query_options['number_list'] = [1, 2]
        expect(response).to include('number_list' => [1, 2])
      end

      context 'is not a number list' do
        it do
          query_options['number_list'] = 1
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'date' do
      it do
        query_options['date'] = '2021-01-01'
        expect(response).to include('date' => Date.new(2021, 1, 1).iso8601)
      end

      context 'is not a date value' do
        it do
          query_options['date'] = true
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end

      context 'is not a valid date' do
        it do
          query_options['date'] = '2021-01-32'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'date_list' do
      it do
        query_options['date_list'] = %w[2021-01-01 2021-01-02]
        expect(response).to include('date_list' => %w[2021-01-01 2021-01-02])
      end

      context 'is not a date list' do
        it do
          query_options['date_list'] = '2021-01-01'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end

      context 'is not a valid date' do
        it do
          query_options['date_list'] = %w[2021-01-01 2021-01-32]
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'datetime' do
      it do
        query_options['datetime'] = '2021-01-01T00:00:00Z'
        expect(response).to include('datetime' => DateTime.new(2021, 1, 1, 0, 0, 0).iso8601)
      end

      context 'is not a datetime value' do
        it do
          query_options['datetime'] = true
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end

      context 'is not a valid datetime' do
        it do
          query_options['datetime'] = '2021-01-01T99:99:99'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'datetime_list' do
      it do
        query_options['datetime_list'] = %w[2021-01-01T00:00:00Z 2021-01-02T00:00:00Z]
        expect(response).to include('datetime_list' => %w[2021-01-01T00:00:00+00:00
                                                          2021-01-02T00:00:00+00:00])
      end

      context 'is not a datetime list' do
        it do
          query_options['datetime_list'] = '2021-01-01T00:00:00Z'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end

      context 'is not a valid datetime' do
        it do
          query_options['datetime_list'] = %w[2021-01-01T00:00:00Z 2021-01-02T99:99:99]
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'bool' do
      it do
        query_options['bool'] = true
        expect(response).to include('bool' => true)
      end

      context 'is not a bool value' do
        it do
          query_options['bool'] = 'bool'
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    describe 'bool_list' do
      it do
        query_options['bool_list'] = [true, false]
        expect(response).to include('bool_list' => [true, false])
      end

      context 'is not a bool list' do
        it do
          query_options['bool_list'] = true
          expect { response }.to raise_error(OdataDuty::InvalidType)
        end
      end
    end

    context 'does not support create' do
      it do
        expect do
          schema.create('DoesNotSupportCreate', context: Context.new,
                                                query_options: { 'id' => '1' })
        end.to raise_error(OdataDuty::NoImplementationError)
      end
    end
  end
end
