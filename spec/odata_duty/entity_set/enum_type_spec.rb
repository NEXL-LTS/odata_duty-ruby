require 'spec_helper'

class TrafficLightEnumType < OdataDuty::EnumType
  member 'Red'
  member 'Green'
  member 'Amber'
end

class SignalEntity < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'light', TrafficLightEnumType, nullable: true
end

class SignalSet < OdataDuty::EntitySet
  entity_type SignalEntity

  def collection
    []
  end

  def create(input)
    OpenStruct.new(id: 1, light: input.light)
  end
end

class ValidLightReadSet < OdataDuty::EntitySet
  entity_type SignalEntity
  url 'ValidLightReads'

  def collection
    [OpenStruct.new(id: 1, light: 'Amber')]
  end
end

class NilLightReadSet < OdataDuty::EntitySet
  entity_type SignalEntity
  url 'NilLightReads'

  def collection
    [OpenStruct.new(id: 1, light: nil)]
  end
end

class InvalidLightReadSet < OdataDuty::EntitySet
  entity_type SignalEntity
  url 'InvalidLightReads'

  def collection
    [OpenStruct.new(id: 1, light: 'Violet')]
  end
end

class SignalSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  namespace 'SignalSpace'
  entity_sets [SignalSet, ValidLightReadSet, NilLightReadSet, InvalidLightReadSet]
end

module EnumNameSpace
  class NestedColorEnumType < OdataDuty::EnumType
    member 'Blue'
  end
end

class BareWordEnum < OdataDuty::EnumType
  member 'One'
end

class SuffixSampleEntity < OdataDuty::EntityType
  property_ref 'id', Integer
  property 'nested', EnumNameSpace::NestedColorEnumType, nullable: true
  property 'bare', BareWordEnum, nullable: true
end

class SuffixSampleSet < OdataDuty::EntitySet
  entity_type SuffixSampleEntity

  def collection
    []
  end
end

class SuffixSampleSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  namespace 'SuffixSpace'
  entity_sets [SuffixSampleSet]
end

RSpec.describe OdataDuty::EnumType do
  describe '$metadata rendering' do
    subject(:metadata) { SignalSchema.metadata_xml }

    it 'names the enum by stripping the trailing EnumType suffix' do
      expect(metadata).to include('<EnumType Name="TrafficLight">')
    end

    it 'emits one Member element per declared member in declaration order' do
      enum = metadata[%r{<EnumType Name="TrafficLight">.*?</EnumType>}m]
      expect(enum.scan(%r{<Member Name="(\w+)" />}).flatten).to eq(%w[Red Green Amber])
    end

    it 'renders the enum-typed property with the derived type name' do
      expect(metadata).to include('Type="SignalSpace.TrafficLight"')
    end
  end

  describe 'name suffix derivation' do
    subject(:metadata) { SuffixSampleSchema.metadata_xml }

    it 'strips a trailing bare Enum suffix' do
      expect(metadata).to include('<EnumType Name="BareWord">')
    end

    it 'uses only the final namespace segment of a nested enum class' do
      expect(metadata).to include('<EnumType Name="NestedColor">')
    end
  end

  describe 'building an enum-typed schema at runtime' do
    def runtime_enum(*member_names)
      enum = Class.new(OdataDuty::EnumType)
      member_names.each { |n| enum.member n }
      Object.const_set("RuntimeSpectrum#{enum.object_id}EnumType", enum)
      enum
    end

    def runtime_set(enum)
      entity = Class.new(OdataDuty::EntityType) do
        property_ref 'id', Integer
        property 'shade', enum, nullable: true
      end
      Object.const_set("RuntimeShadeEntity#{entity.object_id}", entity)
      Class.new(OdataDuty::EntitySet) { entity_type(entity) }.tap do |set|
        set.define_singleton_method(:name) { 'RuntimeShades' }
        set.define_method(:collection) { [] }
      end
    end

    def runtime_metadata(*member_names)
      schema = Class.new(OdataDuty::Schema) do
        base_url 'http://localhost:3000/api'
        namespace 'RuntimeSpace'
      end
      schema.entity_sets([runtime_set(runtime_enum(*member_names))])
      schema.metadata_xml
    end

    it 'appends each declared member in order' do
      enum = runtime_metadata('Cyan', 'Magenta', 'Yellow')[%r{<EnumType.*?</EnumType>}m]
      expect(enum.scan(%r{<Member Name="(\w+)" />}).flatten).to eq(%w[Cyan Magenta Yellow])
    end

    it 'renders an enum with no declared members as an empty EnumType element' do
      expect(runtime_metadata).to match(%r{<EnumType Name="RuntimeSpectrum\d+">\s*</EnumType>})
    end

    it 'renders the enum-typed property using the derived type name' do
      expect(runtime_metadata('Cyan')).to match(/Type="RuntimeSpace\.RuntimeSpectrum\d+"/)
    end
  end

  describe 'rejecting a non-string member declaration' do
    it 'raises because a member name must respond to to_str' do
      expect do
        Class.new(OdataDuty::EnumType) do
          member :NotAString
        end
      end.to raise_error(NoMethodError, /to_str/)
    end
  end

  describe 'value coercion via create (POST body)' do
    def create(body)
      SignalSchema.create('Signal', context: Context.new, query_options: body)
    end

    it 'accepts a value that is a declared member' do
      expect(Oj.load(create('id' => 1, 'light' => 'Green'))['light']).to eq('Green')
    end

    it 'accepts a null value for a nullable enum property' do
      expect(Oj.load(create('id' => 1, 'light' => nil))['light']).to be_nil
    end

    it 'raises for a value that is not a declared member' do
      expect { create('id' => 1, 'light' => 'Purple') }
        .to raise_error(OdataDuty::InvalidType,
                        /Purple is not a valid member of \["Red", "Green", "Amber"\]/)
    end
  end

  describe 'value coercion via execute (read path)' do
    def read(set)
      SignalSchema.execute(set, context: Context.new)
    end

    it 'renders a declared member returned by a resolver' do
      expect(Oj.load(read('ValidLightReads'))['value'].first['light']).to eq('Amber')
    end

    it 'renders null when a resolver returns nil for a nullable enum property' do
      expect(Oj.load(read('NilLightReads'))['value'].first['light']).to be_nil
    end

    it 'raises when a resolver returns a value outside the declared members' do
      expect { read('InvalidLightReads') }
        .to raise_error(OdataDuty::InvalidValue,
                        'Property light must be one of ["Red", "Green", "Amber"] and not Violet')
    end
  end
end
