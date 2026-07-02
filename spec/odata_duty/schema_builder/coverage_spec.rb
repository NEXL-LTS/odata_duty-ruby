require 'spec_helper'

class BuilderCovResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id.to_str }
  end
end

class BuilderCovRaisingResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1')]
  end

  def collection
    @records.first.this_method_does_not_exist
  end
end

class BuilderCovNoArgInitResolver < OdataDuty::SetResolver
  def od_after_init; end

  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'coverage of builder edge cases' do
    def build_schema
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'BuilderCov') do |et|
          et.property_ref 'id', String
        end
        s.add_entity_set(name: 'BuilderCov', entity_type: entity, resolver: 'BuilderCovResolver')
        yield s, entity if block_given?
      end
    end

    it 'exposes a readable inspect string' do
      schema = build_schema
      expect(schema.inspect).to include('SampleSpace').and(include('BuilderCov'))
    end

    it 'raises ResourceNotFoundError when individual returns nil' do
      schema = build_schema
      expect do
        schema.execute("BuilderCov('999')", context: Context.new)
      end.to raise_error(OdataDuty::ResourceNotFoundError, /No such entity/)
    end

    it 'raises for a duplicate type name' do
      expect do
        build_schema do |s, _entity|
          s.add_entity_type(name: 'BuilderCov') { |et| et.property_ref 'id', String }
        end
      end.to raise_error(RuntimeError, /Duplicate BuilderCov type/)
    end

    it 'raises for a duplicate container (entity set) name' do
      expect do
        build_schema do |s, entity|
          s.add_entity_set(name: 'BuilderCov', entity_type: entity,
                           resolver: 'BuilderCovResolver')
        end
      end.to raise_error(RuntimeError, /Duplicate BuilderCov Container/)
    end

    it 'raises for multiple property references' do
      expect do
        SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
          s.add_entity_type(name: 'MultiRef') do |et|
            et.property_ref 'id', String
            et.property_ref 'other', String
          end
        end
      end.to raise_error(RuntimeError, /Multiple Property Reference/)
    end

    it 'surfaces errors raised inside a resolver collection method' do
      schema = SchemaBuilder.build(namespace: 'S', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'BuilderCovRaise') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'BuilderCovRaise', entity_type: entity,
                         resolver: 'BuilderCovRaisingResolver')
      end
      expect do
        schema.execute('BuilderCovRaise', context: Context.new)
      end.to raise_error(NoMethodError)
    end

    it 'raises InitArgsMismatchError when init_args are passed to a no-arg od_after_init' do
      schema = SchemaBuilder.build(namespace: 'S', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'BuilderCovNoArg') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'BuilderCovNoArg', entity_type: entity,
                         resolver: 'BuilderCovNoArgInitResolver', init_args: 'extra')
      end
      expect do
        schema.execute('BuilderCovNoArg', context: Context.new)
      end.to raise_error(OdataDuty::InitArgsMismatchError)
    end
  end
end
