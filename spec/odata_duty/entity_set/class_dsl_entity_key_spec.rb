require 'spec_helper'

class IntegerKeyWidgetEntityType < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'name', String
end

class IntegerKeyWidgetsSet < OdataDuty::EntitySet
  entity_type IntegerKeyWidgetEntityType

  def collection
    [OpenStruct.new(id: 1, name: 'first')]
  end

  def individual(id)
    collection.find { |w| w.id == id }
  end
end

class StringKeyGadgetEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class StringKeyGadgetsSet < OdataDuty::EntitySet
  entity_type StringKeyGadgetEntity

  def collection
    [OpenStruct.new(id: 'a', name: 'first')]
  end
end

module ClassDslKeyNamespace
  class NestedGizmoEntity < OdataDuty::EntityType
    property_ref 'id', String
  end
end

class NestedGizmosSet < OdataDuty::EntitySet
  entity_type ClassDslKeyNamespace::NestedGizmoEntity

  def collection
    []
  end
end

class ClassDslKeySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [IntegerKeyWidgetsSet, StringKeyGadgetsSet, NestedGizmosSet]
end

RSpec.describe OdataDuty::EntityType, 'class-DSL entity key and @odata.id' do
  subject(:schema) { ClassDslKeySchema }

  describe 'the @odata.id built from the key property' do
    it 'renders an integer key unquoted' do
      response = Oj.load(schema.execute('IntegerKeyWidgets', context: Context.new))
      expect(response['value']).to eq(
        [{ '@odata.id' => 'http://localhost:3000/api/IntegerKeyWidgets(1)',
           'id' => 1, 'name' => 'first' }]
      )
    end

    it 'renders a string key single-quoted' do
      response = Oj.load(schema.execute('StringKeyGadgets', context: Context.new))
      expect(response['value']).to eq(
        [{ '@odata.id' => "http://localhost:3000/api/StringKeyGadgets('a')",
           'id' => 'a', 'name' => 'first' }]
      )
    end

    it 'roots the @odata.id at the request base url for the individual path' do
      response = Oj.load(schema.execute('IntegerKeyWidgets(1)', context: Context.new))
      expect(response['@odata.id']).to eq('http://localhost:3000/api/IntegerKeyWidgets(1)')
    end

    it 'honours $select alongside the integer @odata.id' do
      response = Oj.load(schema.execute('IntegerKeyWidgets', context: Context.new,
                                                             query_options: { '$select' => 'id' }))
      expect(response['value']).to eq(
        [{ '@odata.id' => 'http://localhost:3000/api/IntegerKeyWidgets(1)', 'id' => 1 }]
      )
    end

    it 'honours $select alongside the string @odata.id' do
      response = Oj.load(schema.execute('StringKeyGadgets', context: Context.new,
                                                            query_options: { '$select' => 'id' }))
      expect(response['value']).to eq(
        [{ '@odata.id' => "http://localhost:3000/api/StringKeyGadgets('a')", 'id' => 'a' }]
      )
    end
  end

  describe 'the entity type name in $metadata' do
    let(:entity_types) { entity_types_from_doc(parse_xml_from_string(schema.metadata_xml)) }

    it 'strips a trailing EntityType suffix' do
      expect(entity_types).to have_key('IntegerKeyWidget')
    end

    it 'strips a trailing Entity suffix' do
      expect(entity_types).to have_key('StringKeyGadget')
    end

    it 'uses only the last :: segment of a namespaced entity type constant' do
      expect(entity_types).to have_key('NestedGizmo')
    end

    it 'exposes the key property as the single PropertyRef' do
      expect(entity_types.fetch('IntegerKeyWidget').fetch(:keys)).to eq(['id'])
    end

    it 'declares the integer key property as a non-nullable Edm.Int64' do
      expect(entity_types.fetch('IntegerKeyWidget').fetch(:properties))
        .to include(name: 'id', type: 'Edm.Int64', nullable: 'false')
    end

    it 'declares the string key property as a non-nullable Edm.String' do
      expect(entity_types.fetch('StringKeyGadget').fetch(:properties))
        .to include(name: 'id', type: 'Edm.String', nullable: 'false')
    end
  end

  describe 'the key mutability annotation the property_ref default produces' do
    def key_annotation_xml(**property_ref_kwargs)
      entity = Class.new(OdataDuty::EntityType) { property_ref 'id', String, **property_ref_kwargs }
      set = Class.new(OdataDuty::EntitySet) { entity_type(entity) }
      Object.const_set("RuntimeKeyEntity#{entity.object_id}", entity)
      set.define_singleton_method(:entity_type_name) { 'RuntimeKeyEntity' }
      schema_class = Class.new(OdataDuty::Schema) { base_url('http://x/api') }
      schema_class.entity_sets([set])
      schema_class.metadata_xml.split('<Property Name="id"')[1].split('</EntityType>')[0]
    end

    it 'declares the key property non-nullable' do
      expect(key_annotation_xml).to start_with(' Nullable="false"')
    end

    it 'defaults to Org.OData.Core.V1.Computed when neither mutability nor computed is given' do
      expect(key_annotation_xml)
        .to include('<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />')
    end

    it 'leaves no Core annotation when computed: false is given' do
      expect(key_annotation_xml(computed: false)).not_to include('Org.OData.Core.V1')
    end

    it 'respects an explicit mutability: :immutable instead of defaulting to computed' do
      expect(key_annotation_xml(mutability: :immutable))
        .to include('<Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />')
    end

    it 'respects an explicit mutability: :read_write instead of defaulting to computed' do
      expect(key_annotation_xml(mutability: :read_write)).not_to include('Org.OData.Core.V1')
    end
  end

  describe 'declaring a second property reference' do
    it 'raises with the multiple-reference message' do
      expect do
        Class.new(OdataDuty::EntityType) do
          property_ref 'id', String
          property_ref 'other', String
        end
      end.to raise_error(RuntimeError, 'Multiple Property Reference not yet supported')
    end
  end

  describe 'a $select for an unknown property' do
    it 'prepends the entity type source location to the backtrace' do
      expect do
        schema.execute('IntegerKeyWidgets', context: Context.new,
                                            query_options: { '$select' => 'nope' })
      end.to raise_error(OdataDuty::UnknownPropertyError) { |error|
        expect(error.backtrace.first)
          .to eq(Object.const_source_location('IntegerKeyWidgetEntityType').join(':'))
      }
    end
  end
end
