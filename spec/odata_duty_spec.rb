require 'spec_helper'

CountryCity = Struct.new(:country_region, :name, :region) do
  def self.all
    [CountryCity.new('country_region', 'name', 'region')]
  end
end

AddressInfo = Struct.new(:address, :city) do
  def self.all
    [AddressInfo.new('address', CountryCity.new('country', 'name', 'region'))]
  end
end

Person = Struct.new(:id, :user_name, :name, :emails, :address_info, :gender, :concurrency) do
  def self.all
    [
      Person.new('1', 'user1', 'User', ['user@email.com'],
                 [AddressInfo.new('address', CountryCity.new('country', 'name', 'region'))],
                 'Male', 11)
    ]
  end
end

class CountryCityComplex < OdataDuty::ComplexType
  property 'country_region', String, nullable: false
  property 'name', String, nullable: false
  property 'region', String, nullable: false
end

class AddressInfoComplex < OdataDuty::ComplexType
  property 'address', String
  property 'city', CountryCityComplex
end

class PersonGenderEnum < OdataDuty::EnumType
  member 'Male'
  member 'Female'
  member 'Unknown'
end

class PersonEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'user_name', String, nullable: false
  property 'name', String
  property 'emails', [String], nullable: false
  property 'address_info', [AddressInfoComplex], nullable: false
  property 'gender', PersonGenderEnum, nullable: false
  property 'concurrency', Integer, nullable: false
end

class PeopleSet < OdataDuty::EntitySet
  entity_type PersonEntity

  def od_after_init
    @records = Person.all
  end

  def count
    @records.count
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end

class SampleSchema < OdataDuty::Schema
  namespace 'SampleSpace'
  entity_sets [PeopleSet]
end

RSpec.describe OdataDuty do
  subject(:schema) { SampleSchema }

  describe '#index_hash' do
    it do
      expect(SampleSchema.index_hash(Context.new))
        .to eq({
                 '@odata.context': '$metadata',
                 value: [{ kind: 'EntitySet', name: 'People', url: 'People' }]
               })
    end
  end

  describe '#metadata_xml' do
    it 'works' do
      generated_xml = format_xml(SampleSchema.metadata_xml)
      expected_xml = format_xml(File.read("#{__dir__}/metadata.xml"))
      expect(generated_xml).to eq(expected_xml)
    end
  end

  describe '#execute' do
    describe 'collection' do
      it do
        response = Oj.load(SampleSchema.execute('People', context: Context.new))
        expect(response).to eq(
          {
            'value' => [{
              '@odata.id' => 'People(\'1\')',
              'id' => '1', 'user_name' => 'user1', 'name' => 'User',
              'emails' => ['user@email.com'],
              'address_info' => [
                { 'address' => 'address',
                  'city' => { 'country_region' => 'country',
                              'name' => 'name',
                              'region' => 'region' } }
              ],
              'gender' => 'Male', 'concurrency' => 11
            }],
            '@odata.context' => '$metadata#People'
          }
        )
      end
    end

    describe 'count' do
      it do
        response = SampleSchema.execute('People/$count', context: Context.new)
        expect(response).to eq(1)
      end
    end

    describe 'individual' do
      it do
        json_string = SampleSchema.execute("People('1')", context: Context.new)
        response = Oj.load(json_string)
        expect(response).to eq(
          { '@odata.context' => '$metadata#People/$entity',
            '@odata.id' => 'People(\'1\')',
            'id' => '1',
            'user_name' => 'user1',
            'name' => 'User',
            'emails' => ['user@email.com'],
            'address_info' => [{
              'address' => 'address',
              'city' => { 'country_region' => 'country',
                          'name' => 'name',
                          'region' => 'region' }
            }],
            'gender' => 'Male',
            'concurrency' => 11 }
        )
      end
    end
  end
end
