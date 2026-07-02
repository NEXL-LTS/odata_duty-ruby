require 'spec_helper'

class DupNameFoo < OdataDuty::EntityType
  property_ref 'id', String
end

class DupNameFooEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class DupNameFooSet < OdataDuty::EntitySet
  entity_type DupNameFoo
  url 'DupNameFooA'

  def collection
    []
  end
end

class DupNameFooEntitySet < OdataDuty::EntitySet
  entity_type DupNameFooEntity
  url 'DupNameFooB'

  def collection
    []
  end
end

class DuplicateTypeSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [DupNameFooSet, DupNameFooEntitySet]
end

RSpec.describe OdataDuty::Schema, 'duplicate type names' do
  it 'raises when two entity types resolve to the same name' do
    expect { DuplicateTypeSchema.metadata_xml }
      .to raise_error(RuntimeError, /Duplicate DupNameFoo type/)
  end
end

class NonNullableReadEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String, nullable: false
end

class NonNullableReadSet < OdataDuty::EntitySet
  entity_type NonNullableReadEntity

  def collection
    [OpenStruct.new(id: '1', name: nil)]
  end
end

class NonNullableReadSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [NonNullableReadSet]
end

RSpec.describe OdataDuty::EntitySet, 'non-nullable property returning nil on read' do
  it 'raises InvalidValue when a non-nullable property is nil' do
    expect { NonNullableReadSchema.execute('NonNullableRead', context: Context.new) }
      .to raise_error(OdataDuty::InvalidValue, /name cannot be null/)
  end
end

RSpec.describe OdataDuty::EntityType, 'invalid property type' do
  it 'raises when a property is declared with an unsupported type' do
    expect do
      Class.new(OdataDuty::EntityType) do
        property_ref 'id', String
        property 'bad', nil
      end
    end.to raise_error(RuntimeError, /Invalid type nil for bad/)
  end
end
