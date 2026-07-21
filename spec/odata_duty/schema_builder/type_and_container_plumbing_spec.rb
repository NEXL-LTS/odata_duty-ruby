require 'spec_helper'

class PlumbingResolver < OdataDuty::SetResolver
  def collection
    []
  end

  def create(input)
    OpenStruct.new(id: '1', status: input.status)
  end
end

class BadComplexResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1', badge: OpenStruct.new(label: Object.new))]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder, 'type and container name validation' do
    def build(&block)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '', &block)
    end

    it 'rejects an invalid entity type name as an NCName' do
      expect do
        build { |s| s.add_entity_type(name: '9bad') { |et| et.property_ref 'id', String } }
      end.to raise_error(InvalidNCNamesError, '"9bad" is not a valid property name')
    end

    it 'rejects an invalid enum type name as an NCName' do
      expect do
        build { |s| s.add_enum_type(name: '9bad') { |e| e.member 'one' } }
      end.to raise_error(InvalidNCNamesError, '"9bad" is not a valid property name')
    end

    it 'rejects an invalid complex type name as an NCName' do
      expect do
        build { |s| s.add_complex_type(name: '9bad') { |c| c.property 'label', String } }
      end.to raise_error(InvalidNCNamesError, '"9bad" is not a valid property name')
    end

    it 'rejects an invalid entity set (container) name as an NCName' do
      expect do
        build do |s|
          entity = s.add_entity_type(name: 'Plumbing') { |et| et.property_ref 'id', String }
          s.add_entity_set(name: '9bad', entity_type: entity, resolver: 'PlumbingResolver')
        end
      end.to raise_error(InvalidNCNamesError, '"9bad" is not a valid property name')
    end

    it 'keeps a type name even after the caller mutates the original string' do
      type_name = 'PlumbingType'.dup
      schema = build do |s|
        entity = s.add_entity_type(name: type_name) { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'Plumbings', entity_type: entity, resolver: 'PlumbingResolver')
      end
      type_name << '_MUTATED'
      expect(schema.metadata_xml).to include('<EntityType Name="PlumbingType"')
    end
  end

  RSpec.describe SchemaBuilder, 'complex type property declaration location' do
    let(:declared_at) { [] }

    subject(:schema) do
      lines = declared_at
      SchemaBuilder.build(namespace: 'S', host: 'localhost', base_path: '') do |s|
        badge = s.add_complex_type(name: 'BadgeLoc') do |c|
          lines << "#{__FILE__}:#{__LINE__ + 1}"
          c.property 'label', String
        end
        widget = s.add_entity_type(name: 'WidgetLoc') do |et|
          et.property_ref 'id', String
          et.property 'badge', badge
        end
        s.add_entity_set(name: 'WidgetLocs', entity_type: widget, resolver: 'BadComplexResolver')
      end
    end

    it 'records the property declaration site in the coercion error backtrace' do
      backtrace =
        begin
          schema.execute('WidgetLocs', context: Context.new)
          []
        rescue OdataDuty::InvalidValue => e
          e.backtrace
        end
      expect(backtrace).to include(a_string_starting_with(declared_at.first))
    end
  end

  RSpec.describe SchemaBuilder, 'enum coercion on the create path' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        status = s.add_enum_type(name: 'PlumbingStatus') do |e|
          e.member 'Active'
          e.member 'Inactive'
        end
        entity = s.add_entity_type(name: 'PlumbingWidget') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'status', status, nullable: true
        end
        s.add_entity_set(name: 'PlumbingWidgets', entity_type: entity,
                         resolver: 'PlumbingResolver')
      end
    end

    def create(status)
      schema.create('PlumbingWidgets', context: Context.new,
                                       query_options: { 'id' => '1', 'status' => status })
    end

    it 'accepts a declared enum member' do
      expect(Oj.load(create('Active'))).to include('status' => 'Active')
    end

    it 'accepts a null value for the nullable enum property' do
      expect(Oj.load(create(nil))).to include('status' => nil)
    end

    it 'names the offending value and the declared members when the value is not a member' do
      expect { create('Pending') }.to raise_error(
        OdataDuty::InvalidType, /Pending is not a valid member of \[#<OdataDuty::EnumMember/
      )
    end
  end
end
