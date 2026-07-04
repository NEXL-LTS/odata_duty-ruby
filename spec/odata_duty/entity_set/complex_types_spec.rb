require 'spec_helper'

RSpec.describe OdataDuty::EntitySet, 'complex types' do
  let(:address_type) do
    stub_const('ComplexTypesTest::AddressComplexType', Class.new(OdataDuty::ComplexType))
      .tap do |klass|
        klass.property 'street'
        klass.property 'city', OdataDuty::EdmString, nullable: false
      end
  end

  let(:manager_type) do
    address = address_type
    stub_const('ComplexTypesTest::ManagerEntity', Class.new(OdataDuty::EntityType))
      .tap do |klass|
        klass.property_ref 'id', OdataDuty::EdmInt64
        klass.property 'address', address, nullable: true
        klass.property 'boss', klass, nullable: true
      end
  end

  let(:schema) do
    manager = manager_type
    set = stub_const('ComplexTypesTest::ManagersSet', Class.new(OdataDuty::EntitySet))
    set.entity_type manager
    set.define_method(:collection) { [] }
    Class.new(OdataDuty::Schema) do
      namespace 'ComplexTypesTest'
      base_url 'http://example.com'
      entity_sets [ComplexTypesTest::ManagersSet]
    end
  end

  let(:xml) { schema.metadata_xml }

  it 'registers properties declared on the complex type' do
    expect(xml).to include('<Property Name="street" Nullable="true" Type="Edm.String" />')
    expect(xml).to include('<Property Name="city" Nullable="false" Type="Edm.String" />')
  end

  it 'strips the ComplexType suffix and namespace from the name' do
    expect(xml).to include('<ComplexType Name="Address">')
    expect(xml).not_to include('AddressComplexType')
  end

  it 'types entity properties by their complex type name' do
    expect(xml).to include(
      '<Property Name="address" Nullable="true" Type="ComplexTypesTest.Address" />'
    )
  end

  it 'renders a self-referencing entity type exactly once' do
    expect(xml.scan('<EntityType Name=').size).to eq(1)
    expect(xml).to include(
      '<Property Name="boss" Nullable="true" Type="ComplexTypesTest.Manager" />'
    )
  end

  it 'does not allow redefining a property' do
    expect { address_type.property('street') }
      .to raise_error(OdataDuty::PropertyAlreadyDefinedError, 'street is already defined')
  end
end
