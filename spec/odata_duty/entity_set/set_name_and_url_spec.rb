require 'spec_helper'

class NameEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class RenameUrlWithStringSet < OdataDuty::EntitySet
  url 'path_renamed'
  entity_type NameEntity

  def collection
    [OpenStruct.new(id: '1')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class RenamedSet < OdataDuty::EntitySet
  name 'set_renamed'
  entity_type NameEntity

  def collection
    [OpenStruct.new(id: '2')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class RenameBothWithSymbolSet < OdataDuty::EntitySet
  name :RenameWithSymbol
  url :symbol_renamed
  entity_type NameEntity

  def collection
    [OpenStruct.new(id: '1')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class NewNameSet < OdataDuty::EntitySet
  entity_type NameEntity

  def collection
    [OpenStruct.new(id: '4')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class SetDoesNotEnd < OdataDuty::EntitySet
  entity_type NameEntity

  def collection
    [OpenStruct.new(id: '3')]
  end

  def individual(id)
    collection.find { |x| x.id == id }
  end
end

class EntityTestsSchema < OdataDuty::Schema
  entity_sets [NewNameSet, SetDoesNotEnd, RenamedSet, RenameBothWithSymbolSet,
               RenameUrlWithStringSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can Override the default name and/or url' do
  subject(:schema) { EntityTestsSchema }

  describe '#index_hash' do
    let(:index_hash) { schema.index_hash(Context.new) }
    let(:index_values) { index_hash.fetch(:value) }
    let(:entity_set) { index_values.map { |x| x.slice(:name, :url) } }

    it { expect(index_values).to have_attributes(size: 5) }
    it { expect(entity_set).to include(name: 'NewName', url: 'NewName') }
    it { expect(entity_set).to include(name: 'SetDoesNotEnd', url: 'SetDoesNotEnd') }
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
        response = Oj.load(schema.execute('SetDoesNotEnd', context: Context.new))
        expect(response).to eq(
          'value' => [{
            '@odata.id' => 'SetDoesNotEnd(\'3\')',
            'id' => '3'
          }],
          '@odata.context' => '$metadata#SetDoesNotEnd'
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
      parse_xml_from_string(schema.metadata_xml)
    end
    let(:entity_sets) { entity_sets_from_doc(parsed_xml) }

    it { expect(entity_sets).to have_attributes(size: 5) }
    it { expect(entity_sets).to include('NewName' => '.Name') }
    it { expect(entity_sets).to include('SetDoesNotEnd' => '.Name') }
    it { expect(entity_sets).to include('set_renamed' => '.Name') }
    it { expect(entity_sets).to include('RenameWithSymbol' => '.Name') }
    it { expect(entity_sets).to include('RenameUrlWithString' => '.Name') }
  end
end
