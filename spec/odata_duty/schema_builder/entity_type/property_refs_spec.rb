require 'spec_helper'

class StringRefsResolver < OdataDuty::SetResolver
end

class IntegerRefsResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'Can setup property refs' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        string_entity = s.add_entity_type(name: 'StringRef') do |et|
          et.property_ref 'id', String
        end

        integer_entity = s.add_entity_type(name: 'IntegerRef') do |et|
          et.property_ref 'id', Integer
        end

        s.add_entity_set(name: 'StringRefs', entity_type: string_entity,
                         resolver: 'StringRefsResolver')
        s.add_entity_set(name: 'IntegerRefs', entity_type: integer_entity,
                         resolver: 'IntegerRefsResolver')
      end
    end

    describe '#metadata_xml' do
      let(:parsed_xml) do
        parse_xml_from_string(EdmxSchema.metadata_xml(schema))
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
end
