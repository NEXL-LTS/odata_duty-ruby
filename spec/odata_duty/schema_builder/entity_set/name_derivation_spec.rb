require 'spec_helper'

module Admin
  class PeopleResolver < OdataDuty::SetResolver
    def collection = []
  end
end

class DerivedNameResolver < OdataDuty::SetResolver
  def collection = []
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'derives its name from the resolver constant' do
    def build_schema(&block)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '', &block)
    end

    describe 'a namespaced resolver with no explicit name' do
      subject(:schema) do
        build_schema do |s|
          entity = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', String }
          s.add_entity_set(entity_type: entity, resolver: 'Admin::PeopleResolver')
        end
      end

      it 'strips the namespace and the Resolver suffix to derive the entity set name' do
        entity_sets = schema.index_hash.fetch(:value).map { |e| e.fetch(:name) }
        expect(entity_sets).to eq(['People'])
      end

      it 'exposes the derived name in the metadata document' do
        expect(schema.metadata_xml).to include('<EntitySet Name="People"')
      end

      it 'derives the url from the derived name' do
        url = schema.index_hash.fetch(:value).first.fetch(:url)
        expect(url).to eq('People')
      end
    end

    describe 'defensive copying of caller-supplied strings' do
      let(:resolver_name) { 'DerivedNameResolver'.dup }
      let(:name) { 'Original'.dup }
      let(:url) { 'original_url'.dup }

      subject(:schema) do
        built = build_schema do |s|
          entity = s.add_entity_type(name: 'Person') { |et| et.property_ref 'id', String }
          s.add_entity_set(entity_type: entity, resolver: resolver_name, name: name, url: url)
        end
        resolver_name << '_MUTATED'
        name << '_MUTATED'
        url << '_MUTATED'
        built
      end

      it 'keeps the entity set name even after the caller mutates the original string' do
        expect(schema.index_hash.fetch(:value).first.fetch(:name)).to eq('Original')
      end

      it 'keeps the entity set url even after the caller mutates the original string' do
        expect(schema.index_hash.fetch(:value).first.fetch(:url)).to eq('original_url')
      end

      it 'keeps the metadata name even after the caller mutates the original string' do
        expect(schema.metadata_xml).to include('<EntitySet Name="Original"')
      end
    end
  end
end
