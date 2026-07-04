require 'spec_helper'

# An HR domain showing how complex types compose with entity types:
# reusable value objects (Company), nested payloads, and self-references.
module ComplexTypesExample
  class CompanyComplexType < OdataDuty::ComplexType
    property 'name'
    property 'city', String, nullable: false
  end

  class EmployeeEntity < OdataDuty::EntityType
    property_ref 'id', Integer
    property 'employer', CompanyComplexType, nullable: true
  end

  class EmployeesSet < OdataDuty::EntitySet
    entity_type EmployeeEntity

    def od_after_init
      @records = [
        OpenStruct.new(id: 1, employer: nil),
        OpenStruct.new(id: 2, employer: OpenStruct.new(name: 'ACME', city: 'Metropolis'))
      ]
    end

    def collection
      @records
    end
  end

  class ManagerEntity < OdataDuty::EntityType
    property_ref 'id', Integer
    property 'boss', ManagerEntity, nullable: true
  end

  class ManagersSet < OdataDuty::EntitySet
    entity_type ManagerEntity

    def od_after_init
      alice = OpenStruct.new(id: 1, boss: nil)
      @records = [alice, OpenStruct.new(id: 2, boss: alice)]
    end

    def collection
      @records
    end
  end

  class ContractorEntity < OdataDuty::EntityType
    property_ref 'id', Integer
  end

  class ContractorsSet < OdataDuty::EntitySet
    entity_type ContractorEntity

    def collection
      []
    end
  end

  class AuditComplexType < OdataDuty::ComplexType
  end

  class HrSchema < OdataDuty::Schema
    namespace 'HR'
    base_url 'http://localhost:3000/api'
    entity_sets [EmployeesSet, ManagersSet, ContractorsSet]
  end
end

RSpec.describe OdataDuty::EntitySet, 'complex types' do
  let(:xml) { ComplexTypesExample::HrSchema.metadata_xml }

  it 'declares the complex type and its properties in $metadata' do
    expect(xml).to include('<ComplexType Name="Company">')
    expect(xml).to include('<Property Name="name" Nullable="true" Type="Edm.String" />')
    expect(xml).to include('<Property Name="city" Nullable="false" Type="Edm.String" />')
  end

  it 'names the type after the class, minus namespace and ComplexType suffix' do
    expect(xml).not_to include('CompanyComplexType')
    expect(xml).not_to include('ComplexTypesExample')
  end

  it 'types entity properties with the schema-namespaced complex type name' do
    expect(xml).to include('<Property Name="employer" Nullable="true" Type="HR.Company" />')
  end

  it 'returns nested complex values in collection payloads' do
    json = ComplexTypesExample::HrSchema.execute('Employees', context: Context.new,
                                                              query_options: {})
    employers = Oj.load(json).fetch('value').map { |employee| employee['employer'] }
    expect(employers).to eq([nil, { 'name' => 'ACME', 'city' => 'Metropolis' }])
  end

  it 'supports entity types that reference themselves, declared once' do
    expect(xml).to include('<Property Name="boss" Nullable="true" Type="HR.Manager" />')
    expect(xml.scan('<EntityType Name="Manager">').size).to eq(1)
  end

  it 'returns self-referenced values nested in payloads, ending where the data ends' do
    json = ComplexTypesExample::HrSchema.execute('Managers', context: Context.new,
                                                             query_options: {})
    bosses = Oj.load(json).fetch('value').map { |manager| manager['boss'] }
    expect(bosses).to eq([nil, { 'id' => 1, 'boss' => nil }])
  end

  it 'raises when the same property is defined twice' do
    ComplexTypesExample::AuditComplexType.property 'reviewed_at'
    expect { ComplexTypesExample::AuditComplexType.property 'reviewed_at' }
      .to raise_error(OdataDuty::PropertyAlreadyDefinedError, 'reviewed_at is already defined')
  end

  it 'allows adding properties to an already-defined type' do
    ComplexTypesExample::ContractorEntity.property 'billing_address',
                                                   ComplexTypesExample::CompanyComplexType,
                                                   nullable: true
    expect(ComplexTypesExample::HrSchema.metadata_xml)
      .to include('<Property Name="billing_address" Nullable="true" Type="HR.Company" />')
  end
end
