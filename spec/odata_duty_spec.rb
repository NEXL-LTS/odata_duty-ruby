require 'spec_helper'

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

  def create(params)
    address_info = params.address_info.map do |address|
      AddressInfo.new(address.address,
                      CountryCity.new(address.city.country_region,
                                      address.city.name,
                                      address.city.region))
    end
    Person.new('111', params.user_name, params.name, params.emails, address_info, params.gender,
               params.concurrency)
  end
end

class SampleSchema < OdataDuty::Schema
  namespace 'SampleSpace'
  version '1.2.3'
  title 'This is a sample OData service.'
  base_url 'http://localhost'
  entity_sets [PeopleSet]
end

RSpec.describe OdataDuty do
  subject(:schema) { SampleSchema }

  describe '#index_hash' do
    it do
      expect(SampleSchema.index_hash('http://localhost/$metadata'))
        .to eq({
                 '@odata.context': 'http://localhost/$metadata',
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
              '@odata.id' => 'http://localhost/People(\'1\')',
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
            '@odata.context' => 'http://localhost/$metadata#People'
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
          { '@odata.context' => 'http://localhost/$metadata#People/$entity',
            '@odata.id' => 'http://localhost/People(\'1\')',
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

  describe '#create' do
    it do
      attributes = {
        'user_name' => 'user2',
        'name' => 'User2',
        'emails' => ['user2@email.com'],
        'address_info' => [{
          'address' => 'address2',
          'city' => { 'country_region' => 'country2',
                      'name' => 'name2',
                      'region' => 'region2' }
        }],
        'gender' => 'Female',
        'concurrency' => 22
      }
      json_string = SampleSchema.create('People', context: Context.new,
                                                  query_options: attributes)
      response = Oj.load(json_string)
      expect(response).to eq(
        { '@odata.context' => 'http://localhost/$metadata#People/$entity',
          '@odata.id' => 'http://localhost/People(\'111\')',
          'id' => '111',
          'user_name' => 'user2',
          'name' => 'User2',
          'emails' => ['user2@email.com'],
          'address_info' => [{
            'address' => 'address2',
            'city' => { 'country_region' => 'country2',
                        'name' => 'name2',
                        'region' => 'region2' }
          }],
          'gender' => 'Female',
          'concurrency' => 22 }
      )
    end
  end
end
