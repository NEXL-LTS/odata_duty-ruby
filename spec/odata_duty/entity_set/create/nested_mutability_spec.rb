require 'spec_helper'

# Documents that a property's `mutability:` applies to *nested* complex-type values in
# create/update bodies exactly as it does at the top level: dropped values read back as `nil`
# with no error, writable values pass through, and a wrong-typed writable value still raises.

class NestedInnerComplex < OdataDuty::ComplexType
  property 'label', String
  property 'secret', String, mutability: :immutable
end

class NestedAddressComplex < OdataDuty::ComplexType
  property 'street', String
  property 'postcode', String, mutability: :immutable
  property 'code', String, mutability: :non_insertable
  property 'inner', NestedInnerComplex
end

class NestedPersonEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'address', NestedAddressComplex
  property 'addresses', [NestedAddressComplex]
end

class NestedPersonSet < OdataDuty::EntitySet
  entity_type NestedPersonEntity

  def create(input)
    read_back(input)
  end

  def update(_id, input)
    read_back(input)
  end

  private

  def read_back(input)
    address = input.address
    OpenStruct.new(
      id: '1',
      address: address && read_address(address),
      addresses: input.addresses&.map { |a| read_address(a) }
    )
  end

  def read_address(address)
    inner = address.inner
    OpenStruct.new(
      street: address.street, postcode: address.postcode, code: address.code,
      inner: inner && OpenStruct.new(label: inner.label, secret: inner.secret)
    )
  end
end

class NestedPersonSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [NestedPersonSet]
end

RSpec.describe OdataDuty::EntitySet, 'nested-input mutability' do
  subject(:schema) { NestedPersonSchema }

  def create(address)
    Oj.load(schema.create('NestedPerson', context: Context.new,
                                          query_options: { 'id' => '1', 'address' => address }))
  end

  def update(address)
    Oj.load(schema.update("NestedPerson('1')", context: Context.new,
                                               query_options: { 'address' => address }))
  end

  describe 'on update' do
    it 'silently drops a nested immutable value while a writable one passes through' do
      response = update('street' => 'New', 'postcode' => 'XY9')
      expect(response['address']).to include('street' => 'New', 'postcode' => nil)
    end
  end

  describe 'on create' do
    it 'keeps a nested immutable value and drops a nested non_insertable one' do
      response = create('street' => 'Main', 'postcode' => 'AB1', 'code' => 'C1')
      expect(response['address']).to include('street' => 'Main', 'postcode' => 'AB1',
                                             'code' => nil)
    end
  end

  describe 'one level deeper (complex within complex)' do
    it 'drops the deeply-nested immutable value on update' do
      response = update('inner' => { 'label' => 'L', 'secret' => 'S' })
      expect(response['address']['inner']).to include('label' => 'L', 'secret' => nil)
    end

    it 'keeps the deeply-nested immutable value on create' do
      response = create('inner' => { 'label' => 'L', 'secret' => 'S' })
      expect(response['address']['inner']).to include('label' => 'L', 'secret' => 'S')
    end
  end

  describe 'a collection of complex values' do
    it 'applies nested mutability to each element on update' do
      response = Oj.load(
        schema.update("NestedPerson('1')", context: Context.new,
                                           query_options: {
                                             'addresses' => [{ 'street' => 'A',
                                                               'postcode' => 'P1' }]
                                           })
      )
      expect(response['addresses'].first).to include('street' => 'A', 'postcode' => nil)
    end
  end

  describe 'a wrong-typed value on a writable nested property' do
    it 'still raises InvalidType' do
      expect { update('street' => 123) }.to raise_error(OdataDuty::InvalidType)
    end
  end
end
