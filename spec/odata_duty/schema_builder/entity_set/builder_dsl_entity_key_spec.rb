require 'spec_helper'

class BuilderIntegerKeyWidgetsResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: 1, name: 'first')]
  end

  def individual(id)
    collection.find { |w| w.id == id.to_int }
  end
end

class BuilderStringKeyGadgetsResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: 'a', name: 'first')]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'builder-DSL entity key and @odata.id' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        widget = s.add_entity_type(name: 'IntegerKeyWidget') do |et|
          et.property_ref 'id', Integer
          et.property 'name', String
        end
        gadget = s.add_entity_type(name: 'StringKeyGadget') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'IntegerKeyWidgets', entity_type: widget,
                         resolver: 'BuilderIntegerKeyWidgetsResolver')
        s.add_entity_set(name: 'StringKeyGadgets', entity_type: gadget,
                         resolver: 'BuilderStringKeyGadgetsResolver')
      end
    end

    describe 'the @odata.id built from the key property' do
      it 'renders an integer key unquoted' do
        response = Oj.load(schema.execute('IntegerKeyWidgets', context: Context.new))
        expect(response['value']).to eq(
          [{ '@odata.id' => 'https://localhost/api/IntegerKeyWidgets(1)',
             'id' => 1, 'name' => 'first' }]
        )
      end

      it 'renders a string key single-quoted' do
        response = Oj.load(schema.execute('StringKeyGadgets', context: Context.new))
        expect(response['value']).to eq(
          [{ '@odata.id' => "https://localhost/api/StringKeyGadgets('a')",
             'id' => 'a', 'name' => 'first' }]
        )
      end

      it 'roots the integer @odata.id at the request base url for the individual path' do
        response = Oj.load(schema.execute('IntegerKeyWidgets(1)', context: Context.new))
        expect(response['@odata.id']).to eq('https://localhost/api/IntegerKeyWidgets(1)')
      end

      it 'honours $select alongside the integer @odata.id' do
        json = schema.execute('IntegerKeyWidgets', context: Context.new,
                                                   query_options: { '$select' => 'id' })
        expect(Oj.load(json)['value']).to eq(
          [{ '@odata.id' => 'https://localhost/api/IntegerKeyWidgets(1)', 'id' => 1 }]
        )
      end

      it 'honours $select alongside the string @odata.id' do
        json = schema.execute('StringKeyGadgets', context: Context.new,
                                                  query_options: { '$select' => 'id' })
        expect(Oj.load(json)['value']).to eq(
          [{ '@odata.id' => "https://localhost/api/StringKeyGadgets('a')", 'id' => 'a' }]
        )
      end
    end

    describe 'the key mutability annotation the property_ref default produces' do
      def key_property_xml(**property_ref_kwargs)
        metadata_xml = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          entity = s.add_entity_type(name: 'RuntimeKey') do |et|
            et.property_ref 'id', String, **property_ref_kwargs
          end
          s.add_entity_set(name: 'RuntimeKeys', entity_type: entity,
                           resolver: 'BuilderStringKeyGadgetsResolver')
        end.metadata_xml
        metadata_xml.split('<Property Name="id"')[1].split('</EntityType>')[0]
      end

      it 'declares the key property non-nullable' do
        expect(key_property_xml).to include('Nullable="false"')
      end

      it 'defaults to Org.OData.Core.V1.Computed when neither mutability nor computed is given' do
        expect(key_property_xml)
          .to include('<Annotation Term="Org.OData.Core.V1.Computed" Bool="true" />')
      end

      it 'leaves no Core annotation when computed: false is given' do
        expect(key_property_xml(computed: false)).not_to include('Org.OData.Core.V1')
      end

      it 'respects an explicit mutability: :immutable instead of defaulting to computed' do
        expect(key_property_xml(mutability: :immutable))
          .to include('<Annotation Term="Org.OData.Core.V1.Immutable" Bool="true" />')
      end

      it 'respects an explicit mutability: :read_write instead of defaulting to computed' do
        expect(key_property_xml(mutability: :read_write)).not_to include('Org.OData.Core.V1')
      end
    end

    describe 'declaring a second property reference' do
      it 'raises with the multiple-reference message' do
        expect do
          SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
            s.add_entity_type(name: 'TwoKeys') do |et|
              et.property_ref 'id', String
              et.property_ref 'other', String
            end
          end
        end.to raise_error(RuntimeError, 'Multiple Property Reference not yet supported')
      end
    end
  end
end
