require 'spec_helper'

class RenameUrlWithStringResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class RenamedResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '2')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class RenameBothWithSymbolResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class NewNameResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '4')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class ResolverDoesNotEnd < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '3')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can Override the default name and/or url' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', base_url: 'http://localhost') do |s|
        name_entity = s.add_entity_type(name: 'Name') do |et|
          et.property_ref 'id', String
        end

        s.add_entity_set(entity_type: name_entity, resolver: 'RenameUrlWithStringResolver',
                         url: 'path_renamed')
        s.add_entity_set(entity_type: name_entity, resolver: 'RenamedResolver',
                         name: 'set_renamed')
        s.add_entity_set(entity_type: name_entity, resolver: 'RenameBothWithSymbolResolver',
                         name: :RenameWithSymbol, url: :symbol_renamed)
        s.add_entity_set(entity_type: name_entity, resolver: 'NewNameResolver')
        s.add_entity_set(entity_type: name_entity, resolver: 'ResolverDoesNotEnd')
      end
    end

    describe '#index_hash' do
      let(:index_hash) { EdmxSchema.index_hash(schema) }
      let(:index_values) { index_hash.fetch(:value) }
      let(:entity_set) { index_values.map { |x| x.slice(:name, :url) } }

      it { expect(index_values).to have_attributes(size: 5) }
      it { expect(entity_set).to include(name: 'NewName', url: 'NewName') }
      it { expect(entity_set).to include(name: 'ResolverDoesNotEnd', url: 'ResolverDoesNotEnd') }
      it { expect(entity_set).to include(name: 'set_renamed', url: 'set_renamed') }
      it { expect(entity_set).to include(name: 'RenameWithSymbol', url: 'symbol_renamed') }
      it { expect(entity_set).to include(name: 'RenameUrlWithString', url: 'path_renamed') }
    end

    describe '#execute' do
      describe 'collection' do
        it do
          response = Oj.load(schema.execute('symbol_renamed', context: Context.new))
          expect(response).to eq(
            'value' => [{
              '@odata.id' => 'symbol_renamed(\'1\')',
              'id' => '1'
            }],
            '@odata.context' => '$metadata#RenameWithSymbol'
          )
        end

        it do
          response = Oj.load(schema.execute('set_renamed', context: Context.new))
          expect(response).to eq(
            'value' => [{
              '@odata.id' => 'set_renamed(\'2\')',
              'id' => '2'
            }],
            '@odata.context' => '$metadata#set_renamed'
          )
        end

        it do
          response = Oj.load(schema.execute('ResolverDoesNotEnd', context: Context.new))
          expect(response).to eq(
            'value' => [{
              '@odata.id' => 'ResolverDoesNotEnd(\'3\')',
              'id' => '3'
            }],
            '@odata.context' => '$metadata#ResolverDoesNotEnd'
          )
        end

        it do
          response = Oj.load(schema.execute('NewName', context: Context.new))
          expect(response).to eq(
            'value' => [{
              '@odata.id' => 'NewName(\'4\')',
              'id' => '4'
            }],
            '@odata.context' => '$metadata#NewName'
          )
        end
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(EdmxSchema.metadata_xml(schema))
      end
      let(:entity_sets) { entity_sets_from_doc(parsed_xml) }

      it { expect(entity_sets).to have_attributes(size: 5) }
      it { expect(entity_sets).to include('NewName' => 'SampleSpace.Name') }
      it { expect(entity_sets).to include('ResolverDoesNotEnd' => 'SampleSpace.Name') }
      it { expect(entity_sets).to include('set_renamed' => 'SampleSpace.Name') }
      it { expect(entity_sets).to include('RenameWithSymbol' => 'SampleSpace.Name') }
      it { expect(entity_sets).to include('RenameUrlWithString' => 'SampleSpace.Name') }
    end
  end
end
