require 'spec_helper'

module BuilderFilterOrCapture
  module_function

  def predicates
    @predicates ||= []
  end

  def reset
    @predicates = []
  end
end

class FilterOrPeopleResolver < OdataDuty::SetResolver
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
    BuilderFilterOrCapture.predicates.replace(predicates)
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

class FilterlessOrPeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = FilterOrPeopleResolver::ALL_RECORDS
  end

  def collection
    @records
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'flat OR $filter' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        entity = s.add_entity_type(name: 'FilterOrTest') do |et|
          et.property_ref 'id', Integer
          et.property 'name', String
          et.property 'status', String
          et.property 'tags', [String]
        end

        s.add_entity_set(name: 'FilterOrPeople', entity_type: entity,
                         resolver: 'FilterOrPeopleResolver')
        s.add_entity_set(name: 'FilterlessOrPeople', entity_type: entity,
                         resolver: 'FilterlessOrPeopleResolver')
      end
    end

    before { BuilderFilterOrCapture.reset }

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
                                       query_options: { '$filter' =>
                                         "name eq 'Alice' or id gt 2" })
      predicates = BuilderFilterOrCapture.predicates
      expect(predicates.map(&:property_name)).to eq(%i[name id])
      expect(predicates.map(&:operation)).to eq(%i[eq gt])
      expect(predicates.map(&:value)).to eq(['Alice', 2])
    end

    it 'allows mixed operations under one OR' do
      json = schema.execute('FilterOrPeople', context: Context.new,
                                              query_options: { '$filter' => 'id lt 2 or id gt 2' })
      expect(names(json)).to contain_exactly('Alice', 'Carol')
    end

    it 'does not call od_filter_or for AND filters' do
      json = schema.execute('FilterOrPeople', context: Context.new,
                                              query_options: { '$filter' =>
                                                "status eq 'active' and name eq 'Alice'" })
      expect(names(json)).to contain_exactly('Alice')
      expect(BuilderFilterOrCapture.predicates).to be_empty
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
                                         query_options: { '$filter' => "(status eq 'active')" })
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
                                         query_options: { '$filter' => "id eq 1 or id gt 'abc'" })
      end.to raise_error(OdataDuty::InvalidFilterValue)
    end

    describe '#metadata' do
      let(:metadata_xml) { schema.metadata_xml }

      it 'includes FilterRestrictions annotation for OR-filter-enabled entity sets' do
        expect(metadata_xml).to include('<EntitySet Name="FilterOrPeople"')
        expect(metadata_xml).to include('Term="Capabilities.FilterRestrictions"')
        expect(metadata_xml).to include('Property="Filterable" Bool="true"')
        allowed = 'Property="AllowedExpressions" ' \
                  'EnumMember="Capabilities.FilterExpressionType/SingleValue"'
        expect(metadata_xml).to include(allowed)
      end

      it 'does not include FilterRestrictions annotation for non-OR-filter entity sets' do
        filterless_xml = metadata_xml
                         .split('<EntitySet Name="FilterlessOrPeople"')[1]
                         .split('</EntitySet>')[0]
        expect(filterless_xml).not_to include('Capabilities.FilterRestrictions')
      end
    end
  end
end
