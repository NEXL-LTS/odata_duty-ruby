require 'spec_helper'

class RecordingContext
  attr_reader :coerced

  def initialize
    @coerced = []
  end

  def record(value)
    @coerced << value
  end
end

class ContextAwareEnum < OdataDuty::EnumType
  member 'Ops'
  member 'Sales'

  def self.to_value(value, context)
    context.record(value)
    super
  end
end

class ContextCoercionDetails < OdataDuty::ComplexType
  property 'kind', ContextAwareEnum
end

class CollectionContextDetails < OdataDuty::ComplexType
  property 'kinds', [ContextAwareEnum]
end

class ContextCoercionEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'kind', ContextAwareEnum
  property 'details', ContextCoercionDetails
  property 'collection_details', CollectionContextDetails
end

class ContextCoercionSet < OdataDuty::EntitySet
  entity_type ContextCoercionEntity

  def create(input)
    build(input)
  end

  def update(_id, input)
    build(input)
  end

  private

  def build(input)
    details = input.details
    collection_details = input.collection_details
    collection_details&.kinds
    OpenStruct.new(id: '1', kind: input.kind, collection_details: nil,
                   details: details && OpenStruct.new(kind: details.kind))
  end
end

class ContextCoercionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ContextCoercionSet]
end

RSpec.describe OdataDuty::EntitySet do
  subject(:schema) { ContextCoercionSchema }

  describe 'the request context supplied to create/update reaches enum coercion' do
    it 'threads the context into a top-level enum on create' do
      ctx = RecordingContext.new
      json = schema.create('ContextCoercion', context: ctx,
                                              query_options: { 'id' => '1', 'kind' => 'Ops' })
      expect(Oj.load(json)['kind']).to eq('Ops')
      expect(ctx.coerced).to eq(['Ops'])
    end

    it 'threads the context into a top-level enum on update' do
      ctx = RecordingContext.new
      json = schema.update("ContextCoercion('1')", context: ctx,
                                                   query_options: { 'kind' => 'Sales' })
      expect(Oj.load(json)['kind']).to eq('Sales')
      expect(ctx.coerced).to eq(['Sales'])
    end

    it 'threads the context into every element of a collection enum on create' do
      ctx = RecordingContext.new
      schema.create('ContextCoercion', context: ctx,
                                       query_options: {
                                         'id' => '1',
                                         'collection_details' => { 'kinds' => %w[Ops Sales] }
                                       })
      expect(ctx.coerced).to eq(%w[Ops Sales])
    end

    it 'threads the context into an enum nested in a complex type on create' do
      ctx = RecordingContext.new
      json = schema.create('ContextCoercion', context: ctx,
                                              query_options: { 'id' => '1',
                                                               'details' => { 'kind' => 'Ops' } })
      expect(Oj.load(json)['details']['kind']).to eq('Ops')
      expect(ctx.coerced).to include('Ops')
    end

    it 'threads the context into an enum nested in a complex type on update' do
      ctx = RecordingContext.new
      json = schema.update("ContextCoercion('1')", context: ctx,
                                                   query_options: {
                                                     'details' => { 'kind' => 'Sales' }
                                                   })
      expect(Oj.load(json)['details']['kind']).to eq('Sales')
      expect(ctx.coerced).to include('Sales')
    end
  end
end
