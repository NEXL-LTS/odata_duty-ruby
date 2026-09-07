require 'spec_helper'

module Oas2QueryParameterRecords
  def od_after_init
    @records = []
  end

  def collection
    @records
  end
end

class Oas2FilterableQueryParameterResolver < OdataDuty::SetResolver
  include Oas2QueryParameterRecords

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def od_top(top)
    @records = @records[0...top.to_i]
  end

  def od_skip(skip)
    @records = @records[skip.to_i..]
  end
end

class Oas2UnfilterableQueryParameterResolver < OdataDuty::SetResolver
  include Oas2QueryParameterRecords
end

class Oas2FilterOrOnlyQueryParameterResolver < OdataDuty::SetResolver
  include Oas2QueryParameterRecords

  def od_filter_or(predicates)
    @records = @records.select { |r| predicates.any? { |p| p.value == r.user_name } }
  end
end

RSpec.describe OdataDuty::OAS2, 'collection GET query parameters' do
  let(:schema) do
    OdataDuty::SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '/api') do |s|
      person = s.add_entity_type(name: 'Oas2QueryParameterPerson') do |et|
        et.property_ref 'id', String
        et.property 'user_name', String, nullable: false
        et.property 'emails', [String]
      end

      s.add_entity_set(name: 'Filterable', entity_type: person,
                       resolver: 'Oas2FilterableQueryParameterResolver')
      s.add_entity_set(name: 'Unfilterable', entity_type: person,
                       resolver: 'Oas2UnfilterableQueryParameterResolver')
      s.add_entity_set(name: 'FilterOrOnly', entity_type: person,
                       resolver: 'Oas2FilterOrOnlyQueryParameterResolver')
    end
  end

  let(:json) { OdataDuty::OAS2.build_json(schema, context: Context.new) }

  def parameters(set_name)
    json.dig('paths', "/#{set_name}", 'get', 'parameters')
  end

  def parameter(set_name, name)
    parameters(set_name).find { |param| param['name'] == name }
  end

  describe '$filter' do
    it 'advertises $filter for a set with an od_filter_eq hook' do
      expect(parameter('Filterable', '$filter'))
        .to eq('name' => '$filter', 'in' => 'query', 'type' => 'string',
               'description' => 'Filter the results, supporting `and` and flat `or` combinations')
    end

    it 'advertises $filter for a set whose only filter hook is od_filter_or' do
      expect(parameters('FilterOrOnly').map { |param| param['name'] }).to include('$filter')
    end

    it 'omits $filter for a set with no od_filter_* hook' do
      expect(parameters('Unfilterable').map { |param| param['name'] }).not_to include('$filter')
    end

    it 'keeps the ungated $select parameter on a set that cannot filter' do
      expect(parameters('Unfilterable').map { |param| param['name'] }).to eq(['$select'])
    end
  end

  describe '$top and $skip bounds' do
    it 'bounds $top below at zero' do
      expect(parameter('Filterable', '$top'))
        .to eq('name' => '$top', 'in' => 'query', 'type' => 'integer', 'minimum' => 0,
               'description' => 'Number of results to return')
    end

    it 'bounds $skip below at zero' do
      expect(parameter('Filterable', '$skip'))
        .to eq('name' => '$skip', 'in' => 'query', 'type' => 'integer', 'minimum' => 0,
               'description' => 'Number of results to skip')
    end
  end

  describe '$select' do
    it 'enumerates the entity type property names in declaration order' do
      expect(parameter('Filterable', '$select'))
        .to eq('name' => '$select', 'in' => 'query', 'type' => 'array',
               'items' => { 'type' => 'string', 'enum' => %w[id user_name emails] },
               'collectionFormat' => 'csv',
               'description' => 'Comma-separated list of properties to return')
    end
  end

  it 'advertises the supported parameters in OData order' do
    expect(parameters('Filterable').map { |param| param['name'] })
      .to eq(['$filter', '$select', '$top', '$skip'])
  end
end
