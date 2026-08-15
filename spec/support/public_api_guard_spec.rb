require 'spec_helper'
require_relative 'public_api_guard'

class GuardConsumerResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class GuardPlainFixture
  def own_accessor
    :ok
  end
end

class GuardSearchResolver < OdataDuty::SetResolver
  class << self
    attr_accessor :captured_expression
  end

  def collection
    []
  end

  def od_search(search_expression)
    self.class.captured_expression = search_expression
    search_expression.terms.map(&:value)
    search_expression.or?
    []
  end
end

RSpec.describe 'PublicApiGuard' do
  around do |example|
    tracepoint = PublicApiGuard.install
    begin
      example.run
    ensure
      PublicApiGuard.uninstall(tracepoint)
    end
  end

  def build_schema
    OdataDuty::SchemaBuilder.build(namespace: 'GuardSpace') do |s|
      entity = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', String }
      s.add_entity_set(name: 'People', entity_type: entity, resolver: 'GuardConsumerResolver')
    end
  end

  def build_search_schema
    OdataDuty::SchemaBuilder.build(namespace: 'GuardSpace') do |s|
      entity = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', String }
      s.add_entity_set(name: 'People', entity_type: entity, resolver: 'GuardSearchResolver')
    end
  end

  def run_search(query: 'alice')
    build_search_schema.execute('People', context: Context.new,
                                          query_options: { '$search' => query })
  end

  it 'raises when a spec calls an internal method on a builder-DSL gem object' do
    schema = build_schema
    expect { schema.types }.to raise_error(OdataDuty::NonPublicApiError)
  end

  it 'accepts a documented public method on a builder-DSL gem object' do
    schema = build_schema
    expect { schema.execute('People', context: Context.new) }.not_to raise_error
  end

  it 'accepts allowlisted SearchExpression and SearchTerm methods driven via a public hook' do
    expect { run_search }.not_to raise_error
  end

  it 'accepts an allowlisted to_s on a gem search term obtained via a public hook' do
    run_search
    term = GuardSearchResolver.captured_expression.terms.first
    expect { term.to_s }.not_to raise_error
  end

  it 'raises on a non-allowlisted method of a gem search object called from a spec' do
    run_search
    captured = GuardSearchResolver.captured_expression
    expect { captured.operator }.to raise_error(OdataDuty::NonPublicApiError)
  end

  it 'accepts a fixtures own accessor whose owner is the fixture not a gem class' do
    fixture = GuardPlainFixture.new
    expect { fixture.own_accessor }.not_to raise_error
  end

  it 'does not raise on a gem self-call to an internal method driven via execute' do
    schema = build_schema
    expect { schema.execute('People', context: Context.new) }.not_to raise_error
  end

  it 'accepts inspect on a gem object' do
    schema = build_schema
    expect { schema.inspect }.not_to raise_error
  end

  it 'names the class and the method in the NonPublicApiError message' do
    schema = build_schema
    expect { schema.types }.to raise_error(
      OdataDuty::NonPublicApiError,
      /`types` is not part of the public API of OdataDuty::SchemaBuilder::Schema/
    )
  end
end
