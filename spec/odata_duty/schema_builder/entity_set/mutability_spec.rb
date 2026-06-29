require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'mutability keyword validation' do
    def build_entity(&block)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        s.add_entity_type(name: 'MutEntity') { |et| block.call(et) }
      end
    end

    it 'raises ArgumentError for an unknown mutability value naming property and value' do
      expect do
        build_entity { |et| et.property 'bad', String, mutability: :frozen }
      end.to raise_error(ArgumentError, /bad.*frozen|frozen.*bad/)
    end

    it 'raises ArgumentError when both mutability and computed are supplied' do
      expect do
        build_entity do |et|
          et.property 'conflict', String, mutability: :immutable, computed: true
        end
      end.to raise_error(ArgumentError)
    end
  end
end
