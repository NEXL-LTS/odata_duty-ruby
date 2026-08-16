require 'spec_helper'

class StructureCollectionResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

class StructureIndividualResolver < OdataDuty::SetResolver
  def individual(id)
    id
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, 'Schema structure and introspection (builder DSL)' do
    def build(namespace: 'SampleSpace', **kwargs, &block)
      block ||= proc {}
      SchemaBuilder.build(namespace: namespace, **kwargs, &block)
    end

    def with_two_sets
      build do |s|
        entity = s.add_entity_type(name: 'Widget') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'Bravos', entity_type: entity,
                         resolver: 'StructureCollectionResolver')
        s.add_entity_set(name: 'Alphas', entity_type: entity,
                         resolver: 'StructureCollectionResolver')
      end
    end

    def metadata_namespace(schema)
      schema.metadata_xml[/<Schema Namespace="([^"]+)"/, 1]
    end

    def oas2_location(schema)
      OAS2.build_json(schema, context: Context.new).slice('host', 'schemes', 'basePath')
    end

    describe 'attribute defaults, composition and caller-string isolation' do
      # Freezing of the read-back attributes is an internal implementation detail; the
      # consumer-visible contract is that a value handed at build time renders and that
      # later mutating the caller's string cannot corrupt the rendered output.
      it 'renders the given namespace into $metadata, isolated from later source mutation' do
        source = +'MutableNS'
        schema = build(namespace: source)
        source << '-mutated'
        expect(metadata_namespace(schema)).to eq('MutableNS')
      end

      it 'renders the given host/scheme/base_path, isolated from later source mutation' do
        host = +'mutablehost'
        scheme = +'http'
        base_path = +'/mutable'
        schema = build(host: host, scheme: scheme, base_path: base_path)
        host << 'x'
        scheme << 's'
        base_path << 'x'
        expect(oas2_location(schema))
          .to eq('host' => 'mutablehost', 'schemes' => ['http'], 'basePath' => '/mutable')
      end

      it 'defaults the host to localhost when none is given' do
        expect(oas2_location(build)['host']).to eq('localhost')
      end

      it 'defaults the scheme to https when none is given' do
        expect(oas2_location(build)['schemes']).to eq(['https'])
      end

      it 'defaults the base_path to empty when none is given' do
        expect(oas2_location(build)['basePath']).to eq('')
      end

      it 'composes the location from scheme, host and base_path in order' do
        schema = build(scheme: 'http', host: 'example.test', base_path: '/api')
        expect(oas2_location(schema))
          .to eq('host' => 'example.test', 'schemes' => ['http'], 'basePath' => '/api')
      end

      it 'defaults the location to https://localhost when only namespace is given' do
        expect(oas2_location(build))
          .to eq('host' => 'localhost', 'schemes' => ['https'], 'basePath' => '')
      end
    end

    describe 'attribute string coercion' do
      it 'raises when the namespace is not string-coercible' do
        expect { build(namespace: :sym) }.to raise_error(NoMethodError)
      end

      it 'raises when the host is not string-coercible' do
        expect { build(host: :sym) }.to raise_error(NoMethodError)
      end

      it 'raises when the scheme is not string-coercible' do
        expect { build(scheme: :sym) }.to raise_error(NoMethodError)
      end

      it 'raises when the base_path is not string-coercible' do
        expect { build(base_path: :sym) }.to raise_error(NoMethodError)
      end
    end

    describe '#inspect' do
      subject(:inspected) do
        build(base_path: '/inspectpath') do |s|
          badge = s.add_complex_type(name: 'InspectBadge') { |c| c.property 'label', String }
          widget = s.add_entity_type(name: 'InspectWidget') do |et|
            et.property_ref 'id', String
            et.property 'badge', badge
          end
          s.add_entity_set(name: 'InspectWidgets', entity_type: widget,
                           resolver: 'StructureCollectionResolver')
        end.inspect
      end

      it 'renders the schema class, namespace, base_path, container and type names verbatim' do
        expect(inspected).to eq(
          '#<OdataDuty::SchemaBuilder::Schema @namespace=SampleSpace @base_path=/inspectpath  ' \
          'containers=["InspectWidgets"] types=["InspectBadge", "InspectWidget"]>'
        )
      end

      it 'lists container names not their EntitySet values' do
        expect(inspected).to include('containers=["InspectWidgets"]')
      end

      it 'lists type names not their type values' do
        expect(inspected).to include('types=["InspectBadge", "InspectWidget"]')
      end

      it 'lists both container names when more than one set is declared' do
        listing = with_two_sets.inspect
        expect(listing).to include('Bravos', 'Alphas')
      end
    end

    describe 'entity sets in $metadata' do
      it 'includes every declared entity set' do
        xml = with_two_sets.metadata_xml
        expect(xml).to include('<EntitySet Name="Alphas"', '<EntitySet Name="Bravos"')
      end

      it 'lists entity sets sorted alphabetically by name' do
        xml = with_two_sets.metadata_xml
        expect(xml.index('Name="Alphas"')).to be < xml.index('Name="Bravos"')
      end
    end

    describe 'complex_types via $metadata' do
      let(:schema) do
        build do |s|
          s.add_enum_type(name: 'CtStatus') { |e| e.member 'Active' }
          badge = s.add_complex_type(name: 'PlainBadge') { |c| c.property 'label', String }
          widget = s.add_entity_type(name: 'CtWidget') do |et|
            et.property_ref 'id', String
            et.property 'badge', badge
          end
          s.add_entity_set(name: 'CtWidgets', entity_type: widget,
                           resolver: 'StructureCollectionResolver')
        end
      end

      it 'renders only the plain complex type as a <ComplexType>, not entity or enum types' do
        names = schema.metadata_xml.scan(/<ComplexType Name="([^"]+)"/).flatten
        expect(names).to eq(['PlainBadge'])
      end
    end

    describe 'individual_entity_sets via $oas2 paths' do
      let(:schema) do
        build do |s|
          entity = s.add_entity_type(name: 'PathWidget') { |et| et.property_ref 'id', String }
          s.add_entity_set(name: 'CollectionOnly', entity_type: entity,
                           resolver: 'StructureCollectionResolver')
          s.add_entity_set(name: 'HasIndividual', entity_type: entity,
                           resolver: 'StructureIndividualResolver')
        end
      end

      let(:paths) { OAS2.build_json(schema, context: Context.new)['paths'].keys }

      it 'exposes an individual path for a set whose resolver defines individual' do
        expect(paths).to include('/HasIndividual({id})')
      end

      it 'does not expose an individual path for a set without an individual resolver' do
        expect(paths).not_to include('/CollectionOnly({id})')
      end
    end

    describe 'collection_entity_sets via $oas2 paths' do
      let(:schema) do
        build do |s|
          entity = s.add_entity_type(name: 'PathWidget') { |et| et.property_ref 'id', String }
          s.add_entity_set(name: 'CollectionOnly', entity_type: entity,
                           resolver: 'StructureCollectionResolver')
          s.add_entity_set(name: 'HasIndividual', entity_type: entity,
                           resolver: 'StructureIndividualResolver')
        end
      end

      let(:paths) { OAS2.build_json(schema, context: Context.new)['paths'].keys }

      it 'exposes a collection path for a set whose resolver defines collection' do
        expect(paths).to include('/CollectionOnly')
      end

      it 'does not expose a collection path for a set without a collection resolver' do
        expect(paths).not_to include('/HasIndividual')
      end
    end
  end
end
