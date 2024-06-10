require 'spec_helper'

class StringRefEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class StringRefsSet < OdataDuty::EntitySet
  entity_type StringRefEntity
end

class IntegerRefEntity < OdataDuty::EntityType
  property_ref 'id', Integer
end

class IntegerRefsSet < OdataDuty::EntitySet
  entity_type IntegerRefEntity
end

class PropertyRefsTestSchema < OdataDuty::Schema
  entity_sets [StringRefsSet, IntegerRefsSet]
end

RSpec.describe OdataDuty::EntitySet, 'Can setup property refs' do
  subject(:schema) { PropertyRefsTestSchema }

  describe '#metadata_xml' do
    let(:parsed_xml) do
      parse_xml_from_string(schema.metadata_xml)
    end
    let(:entity_types) { entity_types_from_doc(parsed_xml) }
    let(:keys) { entity_type.fetch(:keys) }
    let(:properties) { entity_type.fetch(:properties) }

    it { expect(entity_types.keys).to contain_exactly('StringRef', 'IntegerRef') }

    describe 'StringRefEntity' do
      let(:entity_type) { entity_types['StringRef'] }

      it { expect(keys).to eq(['id']) }
      it { expect(properties).to eq([name: 'id', nullable: 'false', type: 'Edm.String']) }
    end

    describe 'IntegerRefEntity' do
      let(:entity_type) { entity_types['IntegerRef'] }

      it { expect(keys).to eq(['id']) }
      it { expect(properties).to eq([name: 'id', nullable: 'false', type: 'Edm.Int64']) }
    end
  end
end
