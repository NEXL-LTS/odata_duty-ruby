require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EntityType, 'mutability keyword validation' do
    def build_entity(&block)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        s.add_entity_type(name: 'MutEntity') { |et| block.call(et) }
      end
    end

    it 'accepts mutability: :non_insertable' do
      expect do
        build_entity { |et| et.property 'status', String, mutability: :non_insertable }
      end.not_to raise_error
    end

    it 'raises ArgumentError for an unknown mutability value naming property and value' do
      expect do
        build_entity { |et| et.property 'bad', String, mutability: :frozen }
      end.to raise_error(ArgumentError, /bad.*frozen|frozen.*bad/)
    end

    it 'lists all four valid mutability values in the rejection message' do
      expect do
        build_entity { |et| et.property 'bad', String, mutability: :frozen }
      end.to raise_error(ArgumentError,
                         /read_write.*immutable.*non_insertable.*computed/m)
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
