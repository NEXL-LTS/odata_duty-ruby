require 'spec_helper'

RSpec.describe OdataDuty::EntityType, 'mutability keyword validation' do
  it 'accepts mutability: :non_insertable' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'status', String, mutability: :non_insertable
      end
    end.not_to raise_error
  end

  it 'raises ArgumentError for an unknown mutability value naming property and value' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'bad', String, mutability: :frozen
      end
    end.to raise_error(ArgumentError, /bad.*frozen|frozen.*bad/)
  end

  it 'lists all four valid mutability values in the rejection message' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'bad', String, mutability: :frozen
      end
    end.to raise_error(ArgumentError,
                       /read_write.*immutable.*non_insertable.*computed/m)
  end

  it 'raises ArgumentError when both mutability and computed are supplied' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'conflict', String, mutability: :immutable, computed: true
      end
    end.to raise_error(ArgumentError)
  end
end
