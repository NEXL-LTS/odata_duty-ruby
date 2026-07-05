require 'spec_helper'

class BuilderRecordingContext
  attr_reader :coerced

  def initialize
    @coerced = []
  end

  def record(value)
    @coerced << value
  end
end

class BuilderContextAwareEnum < OdataDuty::EnumType
  member 'Ops'
  member 'Sales'

  def self.to_value(value, context)
    context.record(value)
    super
  end
end

class BuilderContextCoercionResolver < OdataDuty::SetResolver
  def create(input)
    build(input)
  end

  def update(_id, input)
    build(input)
  end

  private

  def build(input)
    details = input.details
    OpenStruct.new(id: '1', kind: input.kind,
                   details: details && OpenStruct.new(kind: details.kind))
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        details = s.add_complex_type(name: 'BuilderContextCoercionDetails') do |ct|
          ct.property 'kind', BuilderContextAwareEnum
        end
        entity = s.add_entity_type(name: 'BuilderContextCoercionEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'kind', BuilderContextAwareEnum
          et.property 'details', details
        end
        s.add_entity_set(name: 'BuilderContextCoercion', entity_type: entity,
                         resolver: 'BuilderContextCoercionResolver')
      end
    end

    describe 'the request context supplied to create/update reaches enum coercion' do
      it 'threads the context into a top-level enum on create' do
        ctx = BuilderRecordingContext.new
        json = schema.create('BuilderContextCoercion', context: ctx,
                                                       query_options: { 'id' => '1',
                                                                        'kind' => 'Ops' })
        expect(Oj.load(json)['kind']).to eq('Ops')
        expect(ctx.coerced).to eq(['Ops'])
      end

      it 'threads the context into a top-level enum on update' do
        ctx = BuilderRecordingContext.new
        json = schema.update("BuilderContextCoercion('1')", context: ctx,
                                                            query_options: { 'kind' => 'Sales' })
        expect(Oj.load(json)['kind']).to eq('Sales')
        expect(ctx.coerced).to eq(['Sales'])
      end

      it 'threads the context into an enum nested in a complex type on create' do
        ctx = BuilderRecordingContext.new
        json = schema.create('BuilderContextCoercion', context: ctx,
                                                       query_options: {
                                                         'id' => '1',
                                                         'details' => { 'kind' => 'Ops' }
                                                       })
        expect(Oj.load(json)['details']['kind']).to eq('Ops')
        expect(ctx.coerced).to include('Ops')
      end

      it 'threads the context into an enum nested in a complex type on update' do
        ctx = BuilderRecordingContext.new
        json = schema.update("BuilderContextCoercion('1')", context: ctx,
                                                            query_options: {
                                                              'details' => { 'kind' => 'Sales' }
                                                            })
        expect(Oj.load(json)['details']['kind']).to eq('Sales')
        expect(ctx.coerced).to include('Sales')
      end
    end
  end
end
