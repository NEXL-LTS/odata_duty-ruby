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

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'decorates errors with resolver hook locations' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'ErrorDecoration') do |et|
          et.property_ref 'id', String
        end

        s.add_entity_set(name: 'CollectionRaises', entity_type: entity,
                         resolver: 'BuilderCollectionRaisesResolver')
        s.add_entity_set(name: 'IndividualRaises', entity_type: entity,
                         resolver: 'BuilderIndividualRaisesResolver')
      end
    end

    def resolver_method_location(resolver, method_name)
      resolver.instance_method(method_name).source_location.join(':')
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
  end
end
