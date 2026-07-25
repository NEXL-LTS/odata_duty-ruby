require 'spec_helper'

class SchemaDeclColor < OdataDuty::EnumType
  member 'Red'
  member 'Green'
end

class SchemaDeclAddress < OdataDuty::ComplexType
  property 'street', String
end

class SchemaDeclWidgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
  property 'color', SchemaDeclColor
  property 'address', SchemaDeclAddress
end

class SchemaDeclWidget
  attr_reader :id, :name, :color, :address

  def initialize(id, name)
    @id = id
    @name = name
    @color = nil
    @address = nil
  end

  def self.all
    [new('1', 'First'), new('2', 'Second')]
  end
end

class SchemaDeclWidgetSet < OdataDuty::EntitySet
  entity_type SchemaDeclWidgetEntity
  name 'Widgets'
  url 'Widgets'

  def od_after_init
    @records = SchemaDeclWidget.all
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end

  def count
    @records.count
  end
end

class SchemaDeclGadgetEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class SchemaDeclGadgetSet < OdataDuty::EntitySet
  entity_type SchemaDeclGadgetEntity
  name 'Gadgets'
  url 'Gadgets'

  def collection
    []
  end
end

class SchemaDeclDup < OdataDuty::EntityType
  property_ref 'id', String
end

class SchemaDeclDupEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class SchemaDeclDupSetA < OdataDuty::EntitySet
  entity_type SchemaDeclDup
  url 'SchemaDeclDupA'

  def collection
    []
  end
end

class SchemaDeclDupSetB < OdataDuty::EntitySet
  entity_type SchemaDeclDupEntity
  url 'SchemaDeclDupB'

  def collection
    []
  end
end

class SchemaDeclDupSchema < OdataDuty::Schema
  namespace 'SchemaDeclDupSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [SchemaDeclDupSetA, SchemaDeclDupSetB]
end

# An enum type and an entity type that both derive to the name "CheckEnumDup".
class CheckEnumDup < OdataDuty::EnumType
  member 'On'
end

class CheckEnumDupEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'state', CheckEnumDup
end

class CheckEnumDupSet < OdataDuty::EntitySet
  entity_type CheckEnumDupEntity
  url 'CheckEnumDupSet'

  def collection
    []
  end
end

class CheckEnumDupSchema < OdataDuty::Schema
  namespace 'CheckEnumDupSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [CheckEnumDupSet]
end

# A complex type and an entity type that both derive to the name "CheckComplexDup".
class CheckComplexDup < OdataDuty::ComplexType
  property 'label', String
end

class CheckComplexDupEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'detail', CheckComplexDup
end

class CheckComplexDupSet < OdataDuty::EntitySet
  entity_type CheckComplexDupEntity
  url 'CheckComplexDupSet'

  def collection
    []
  end
end

class CheckComplexDupSchema < OdataDuty::Schema
  namespace 'CheckComplexDupSpace'
  base_url 'http://localhost:3000/api'
  entity_sets [CheckComplexDupSet]
end

class SchemaDeclSchema < OdataDuty::Schema
  namespace 'SchemaDeclSpace'
  title 'Schema Declaration Service'
  version '4.5.6'
  base_url 'http://localhost:3000/api'
  entity_sets [SchemaDeclWidgetSet, SchemaDeclGadgetSet]
end

RSpec.describe OdataDuty::Schema, 'class-DSL declarations and metadata' do
  subject(:metadata_xml) { SchemaDeclSchema.metadata_xml }

  describe 'namespace' do
    it 'renders the declared namespace on the Schema element' do
      expect(metadata_xml).to include('<Schema Namespace="SchemaDeclSpace"')
    end

    it 'uses the namespace to qualify entity-container entity types' do
      expect(metadata_xml).to include('EntityType="SchemaDeclSpace.SchemaDeclWidget"')
    end

    it 'reads back the exact namespace that was declared on the schema' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'FreshlyDeclaredSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.namespace).to eq('FreshlyDeclaredSpace')
    end

    it 'leaves the namespace unset when none is declared' do
      schema = Class.new(OdataDuty::Schema) do
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.namespace).to be_nil
    end
  end

  describe 'title' do
    it 'renders the declared title as the Title annotation string' do
      expect(metadata_xml).to include(
        '<Annotation Term="SchemaDeclSpace.Title" String="Schema Declaration Service" />'
      )
    end

    it 'reads back the exact title that was declared on the schema' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'TitleSpace'
        title 'A Freshly Declared Title'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.title).to eq('A Freshly Declared Title')
    end

    it 'omits the Title annotation entirely when no title is declared' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'NoTitleSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.title).to be_nil
      expect(schema.metadata_xml).not_to include('.Title" String=')
    end
  end

  describe 'version' do
    it 'renders the declared version as the Version annotation string' do
      expect(metadata_xml).to include(
        '<Annotation Term="SchemaDeclSpace.Version" String="4.5.6" />'
      )
    end

    it 'reads back the exact version that was declared on the schema' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'VersionSpace'
        version '9.8.7'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.version).to eq('9.8.7')
    end

    it 'omits the Version annotation entirely when no version is declared' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'NoVersionSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.version).to be_nil
      expect(schema.metadata_xml).not_to include('.Version" String=')
    end
  end

  describe 'base_url' do
    it 'surfaces the declared base_url as an absolute id in collection payloads' do
      response = Oj.load(SchemaDeclSchema.execute('Widgets', context: Context.new))

      expect(response['@odata.context'])
        .to eq('http://localhost:3000/api/$metadata#Widgets')
      expect(response['value'].first['@odata.id'])
        .to eq("http://localhost:3000/api/Widgets('1')")
    end

    it 'reads back the exact base_url that was declared on the schema' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'BaseUrlSpace'
        base_url 'http://example.test/svc'
        entity_sets [SchemaDeclGadgetSet]
      end

      expect(schema.base_url).to eq('http://example.test/svc')
    end
  end

  describe 'entity_sets dedup' do
    it 'renders one EntitySet container entry when the same set is declared twice' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'DupSetSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet, SchemaDeclGadgetSet]
      end

      gadget_entries = schema.metadata_xml.scan('<EntitySet Name="Gadgets"')

      expect(gadget_entries.length).to eq(1)
    end

    it 'reads back the declared sets deduplicated' do
      schema = Class.new(OdataDuty::Schema) do
        namespace 'DupReadSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclWidgetSet, SchemaDeclGadgetSet, SchemaDeclWidgetSet]
      end

      expect(schema.entity_sets).to eq([SchemaDeclWidgetSet, SchemaDeclGadgetSet])
    end
  end

  describe 'metadata_types uniqueness' do
    it 'renders a shared entity type once even when two sets reference it' do
      shared = Class.new(OdataDuty::Schema) do
        namespace 'SharedTypeSpace'
        base_url 'http://localhost:3000/api'
        entity_sets [SchemaDeclGadgetSet, Class.new(OdataDuty::EntitySet) do
          entity_type SchemaDeclGadgetEntity
          name 'GadgetsToo'
          url 'GadgetsToo'
          def collection = []
        end]
      end

      type_defs = shared.metadata_xml.scan('<EntityType Name="SchemaDeclGadget">')

      expect(type_defs.length).to eq(1)
    end
  end

  describe 'type selectors' do
    it 'renders the declared enum type under EnumType exactly once' do
      expect(metadata_xml.scan('<EnumType Name="SchemaDeclColor">').length).to eq(1)
    end

    it 'renders the declared complex type under ComplexType exactly once' do
      expect(metadata_xml.scan('<ComplexType Name="SchemaDeclAddress">').length).to eq(1)
    end

    it 'renders the declared entity types under EntityType' do
      expect(metadata_xml).to include('<EntityType Name="SchemaDeclWidget">')
      expect(metadata_xml).to include('<EntityType Name="SchemaDeclGadget">')
    end

    it 'does not render the enum type as a ComplexType or EntityType' do
      expect(metadata_xml).not_to include('<ComplexType Name="SchemaDeclColor"')
      expect(metadata_xml).not_to include('<EntityType Name="SchemaDeclColor"')
    end

    it 'does not render the complex type as an EnumType or EntityType' do
      expect(metadata_xml).not_to include('<EnumType Name="SchemaDeclAddress"')
      expect(metadata_xml).not_to include('<EntityType Name="SchemaDeclAddress"')
    end

    it 'does not render an entity type as an EnumType or ComplexType' do
      expect(metadata_xml).not_to include('<EnumType Name="SchemaDeclWidget"')
      expect(metadata_xml).not_to include('<ComplexType Name="SchemaDeclWidget"')
    end
  end

  describe 'duplicate type name checking' do
    it 'renders successfully for a schema whose type names are all unique' do
      expect { metadata_xml }.not_to raise_error
    end

    it 'raises a Duplicate <Name> type error when two types share a name' do
      expect { SchemaDeclDupSchema.metadata_xml }
        .to raise_error(RuntimeError, /Duplicate SchemaDeclDup type/)
    end

    it 'detects a clash between an enum type name and an entity type name' do
      expect { CheckEnumDupSchema.metadata_xml }
        .to raise_error(RuntimeError, /Duplicate CheckEnumDup type/)
    end

    it 'detects a clash between a complex type name and an entity type name' do
      expect { CheckComplexDupSchema.metadata_xml }
        .to raise_error(RuntimeError, /Duplicate CheckComplexDup type/)
    end
  end

  describe '.index_hash' do
    subject(:index) { SchemaDeclSchema.index_hash('http://localhost:3000/api/$metadata') }

    it 'sets @odata.context to the passed metadata url' do
      expect(index[:'@odata.context']).to eq('http://localhost:3000/api/$metadata')
    end

    it 'lists each declared entity set with its name, kind and url' do
      expect(index[:value]).to contain_exactly(
        { name: 'Widgets', kind: 'EntitySet', url: 'Widgets' },
        { name: 'Gadgets', kind: 'EntitySet', url: 'Gadgets' }
      )
    end
  end
end
