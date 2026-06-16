require 'spec_helper'

module FilterOrCapture
  module_function

  def predicates
    @predicates ||= []
  end

  def reset
    @predicates = []
  end
end

class FilterOrTestEntity < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'name', String
  property 'status', String
  property 'tags', [String]
end

class FilterOrPeopleSet < OdataDuty::EntitySet
  entity_type FilterOrTestEntity

  ALL_RECORDS = [
    OpenStruct.new(id: 1, name: 'Alice', status: 'active'),
    OpenStruct.new(id: 2, name: 'Bob', status: 'pending'),
    OpenStruct.new(id: 3, name: 'Carol', status: 'archived')
  ].freeze

  def od_after_init
    @records = ALL_RECORDS
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def od_filter_or(predicates)
    FilterOrCapture.predicates.replace(predicates)
    @records = @records.select do |r|
      predicates.any? { |p| matches?(r, p) }
    end
  end

  def collection
    @records
  end

  private

  def matches?(record, predicate)
    actual = record.public_send(predicate.property_name)
    case predicate.operation
    when :eq then actual == predicate.value
    when :gt then actual > predicate.value
    when :lt then actual < predicate.value
    else false
    end
  end
end

class FilterlessOrPeopleSet < OdataDuty::EntitySet
  entity_type FilterOrTestEntity

  def od_after_init
    @records = FilterOrPeopleSet::ALL_RECORDS
  end

  def collection
    @records
  end
end

class FilterOrTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterOrPeopleSet, FilterlessOrPeopleSet]
end

RSpec.describe OdataDuty::EntitySet, 'flat OR $filter' do
  subject(:schema) { FilterOrTestSchema }

  before { FilterOrCapture.reset }

  def names(json_string)
    Oj.load(json_string)['value'].map { |v| v['name'] }
  end

  it 'returns the union of both predicates' do
    json = schema.execute('FilterOrPeople', context: Context.new,
                                            query_options: { '$filter' =>
                                              "status eq 'active' or status eq 'pending'" })
    expect(names(json)).to contain_exactly('Alice', 'Bob')
  end

  it 'passes FilterPredicate objects with coerced values to od_filter_or' do
    schema.execute('FilterOrPeople', context: Context.new,
                                     query_options: { '$filter' => "name eq 'Alice' or id gt 2" })
    predicates = FilterOrCapture.predicates
    expect(predicates.map(&:property_name)).to eq(%i[name id])
    expect(predicates.map(&:operation)).to eq(%i[eq gt])
    expect(predicates.map(&:value)).to eq(['Alice', 2])
  end

  it 'allows mixed operations under one OR' do
    json = schema.execute('FilterOrPeople', context: Context.new,
                                            query_options: { '$filter' =>
                                              'id lt 2 or id gt 2' })
    expect(names(json)).to contain_exactly('Alice', 'Carol')
  end

  it 'does not call od_filter_or for AND filters' do
    json = schema.execute('FilterOrPeople', context: Context.new,
                                            query_options: { '$filter' =>
                                              "status eq 'active' and name eq 'Alice'" })
    expect(names(json)).to contain_exactly('Alice')
    expect(FilterOrCapture.predicates).to be_empty
  end

  it 'raises for mixed AND/OR' do
    expect do
      schema.execute('FilterOrPeople', context: Context.new,
                                       query_options: { '$filter' =>
                                         'id eq 1 and id eq 2 or id eq 3' })
    end.to raise_error(OdataDuty::NotYetSupportedError, %r{mixed AND/OR not supported})
  end

  it 'raises for parentheses' do
    expect do
      schema.execute('FilterOrPeople', context: Context.new,
                                       query_options: { '$filter' =>
                                         "(status eq 'active')" })
    end.to raise_error(OdataDuty::NotYetSupportedError)
  end

  it 'raises when od_filter_or is not implemented' do
    expect do
      schema.execute('FilterlessOrPeople', context: Context.new,
                                           query_options: { '$filter' =>
                                             "status eq 'active' or status eq 'pending'" })
    end.to raise_error(OdataDuty::NoImplementationError, /OR filtering not supported/)
  end

  it 'raises for unknown property in a predicate' do
    expect do
      schema.execute('FilterOrPeople', context: Context.new,
                                       query_options: { '$filter' =>
                                         "status eq 'active' or bogus eq 'x'" })
    end.to raise_error(OdataDuty::UnknownPropertyError)
  end

  it 'raises when an OR predicate targets a collection property' do
    expect do
      schema.execute('FilterOrPeople', context: Context.new,
                                       query_options: { '$filter' =>
                                         "status eq 'active' or tags eq 'x'" })
    end.to raise_error(OdataDuty::InvalidQueryOptionError)
  end

  it 'raises for an uncoercible value' do
    expect do
      schema.execute('FilterOrPeople', context: Context.new,
                                       query_options: { '$filter' =>
                                         "id eq 1 or id gt 'abc'" })
    end.to raise_error(OdataDuty::InvalidFilterValue)
  end
end
