require 'spec_helper'

class FilterDateCoercionEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'birth_date', Date
  property 'seen_at', DateTime
end

class FilterDateCoercionSet < OdataDuty::EntitySet
  entity_type FilterDateCoercionEntity

  RECORDS = [
    OpenStruct.new(id: '1', birth_date: '2021-01-01', seen_at: '2021-01-01T00:00:00+00:00'),
    OpenStruct.new(id: '2', birth_date: '2022-02-02', seen_at: '2022-02-02T00:00:00+00:00')
  ].freeze

  def od_after_init
    @records = RECORDS
  end

  def od_filter_eq(property_name, value)
    FilterDateCoercionCapture.record(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

module FilterDateCoercionCapture
  module_function

  def record(property_name, value)
    captured[property_name] = value
  end

  def captured
    @captured ||= {}
  end

  def reset
    @captured = {}
  end
end

class FilterDateCoercionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterDateCoercionSet]
end

RSpec.describe OdataDuty::EntitySet, 'Edm.Date / Edm.DateTimeOffset $filter coercion' do
  subject(:schema) { FilterDateCoercionSchema }

  before { FilterDateCoercionCapture.reset }

  def ids(json_string)
    Oj.load(json_string)['value'].map { |v| v['id'] }
  end

  describe 'Edm.Date' do
    it 'hands od_filter_eq the ISO 8601 String, not a Date object' do
      schema.execute('FilterDateCoercion', context: Context.new,
                                           query_options: {
                                             '$filter' => 'birth_date eq 2021-01-01'
                                           })
      value = FilterDateCoercionCapture.captured[:birth_date]
      expect(value).to be_a(String)
      expect(value).to eq('2021-01-01')
    end

    it 'matches a record whose stored value is the ISO 8601 String' do
      json = schema.execute('FilterDateCoercion', context: Context.new,
                                                  query_options: {
                                                    '$filter' => 'birth_date eq 2021-01-01'
                                                  })
      expect(ids(json)).to contain_exactly('1')
    end
  end

  describe 'Edm.DateTimeOffset' do
    it 'hands od_filter_eq the ISO 8601 String, not a DateTime object' do
      schema.execute('FilterDateCoercion', context: Context.new,
                                           query_options: {
                                             '$filter' => 'seen_at eq 2021-01-01T00:00:00Z'
                                           })
      value = FilterDateCoercionCapture.captured[:seen_at]
      expect(value).to be_a(String)
      expect(value).to eq('2021-01-01T00:00:00+00:00')
    end

    it 'matches a record whose stored value is the ISO 8601 String' do
      json = schema.execute('FilterDateCoercion', context: Context.new,
                                                  query_options: {
                                                    '$filter' => 'seen_at eq 2021-01-01T00:00:00Z'
                                                  })
      expect(ids(json)).to contain_exactly('1')
    end
  end
end
