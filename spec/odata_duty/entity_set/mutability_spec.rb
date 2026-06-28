require 'spec_helper'

RSpec.describe OdataDuty::EntityType, 'mutability keyword validation' do
  it 'raises ArgumentError for an unknown mutability value naming property and value' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'bad', String, mutability: :frozen
      end
    end.to raise_error(ArgumentError, /bad.*frozen|frozen.*bad/)
  end

  it 'raises ArgumentError when both mutability and computed are supplied' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property 'conflict', String, mutability: :immutable, computed: true
      end
    end.to raise_error(ArgumentError)
  end
end
