require 'spec_helper'

class BuilderCollectionRaisesResolver < OdataDuty::SetResolver
  def od_after_init
    @seed = true
  end

  def collection
    raise 'boom in collection'
  end
end

class BuilderIndividualRaisesResolver < OdataDuty::SetResolver
  def od_after_init
    @seed = true
  end

  def individual(_id)
    raise 'boom in individual'
  end
end

class BuilderNoAfterInitCollectionRaisesResolver < OdataDuty::SetResolver
  def collection
    raise 'boom without after init'
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'decorates errors with resolver hook locations' do
    let(:collection_defined_at) { {} }

    subject(:schema) do
      call_sites = collection_defined_at
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'ErrorDecoration') do |et|
          et.property_ref 'id', String
        end

        call_sites[:with_after_init] = "#{__FILE__}:#{__LINE__ + 1}"
        s.add_entity_set(name: 'CollectionRaises', entity_type: entity,
                         resolver: 'BuilderCollectionRaisesResolver')
        s.add_entity_set(name: 'IndividualRaises', entity_type: entity,
                         resolver: 'BuilderIndividualRaisesResolver')
        call_sites[:without_after_init] = "#{__FILE__}:#{__LINE__ + 1}"
        s.add_entity_set(name: 'NoAfterInitRaises', entity_type: entity,
                         resolver: 'BuilderNoAfterInitCollectionRaisesResolver')
      end
    end

    def resolver_method_location(resolver, method_name)
      resolver.instance_method(method_name).source_location.join(':')
    end

    def raised_from(path)
      schema.execute(path, context: Context.new)
      nil
    rescue StandardError => e
      e
    end

    it 'prepends the resolver collection location onto a raised error backtrace' do
      raised = nil
      begin
        schema.execute('CollectionRaises', context: Context.new)
      rescue StandardError => e
        raised = e
      end
      expect(raised.message).to eq('boom in collection')
      expect(raised.backtrace.first)
        .to eq(resolver_method_location(BuilderCollectionRaisesResolver, :collection))
    end

    it 'prepends the resolver individual location onto a raised error backtrace' do
      raised = nil
      begin
        schema.execute("IndividualRaises('1')", context: Context.new)
      rescue StandardError => e
        raised = e
      end
      expect(raised.message).to eq('boom in individual')
      expect(raised.backtrace.first)
        .to eq(resolver_method_location(BuilderIndividualRaisesResolver, :individual))
    end

    it 'prefixes the backtrace with method, od_after_init, add_entity_set locations in order' do
      raised = raised_from('CollectionRaises')
      expect(raised.backtrace[0])
        .to eq(resolver_method_location(BuilderCollectionRaisesResolver, :collection))
      expect(raised.backtrace[1])
        .to eq(resolver_method_location(BuilderCollectionRaisesResolver, :od_after_init))
      expect(raised.backtrace[2]).to start_with(collection_defined_at.fetch(:with_after_init))
    end

    it 'omits the od_after_init frame when the resolver does not define od_after_init' do
      raised = raised_from('NoAfterInitRaises')
      expect(raised.backtrace[0])
        .to eq(resolver_method_location(BuilderNoAfterInitCollectionRaisesResolver, :collection))
      expect(raised.backtrace[1]).to start_with(collection_defined_at.fetch(:without_after_init))
    end
  end
end
