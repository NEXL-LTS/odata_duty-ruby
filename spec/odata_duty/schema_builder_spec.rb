require 'spec_helper'

class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = if context.query_options['none'] == 'true'
                 []
               else
                 Person.all
               end
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

module OdataDuty
  RSpec.describe SchemaBuilder do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', base_url: 'http://localhost') do |s|
        country_city_complex = s.add_complex_type(name: 'CountryCity') do |c|
          c.property 'country_region', String, nullable: false
          c.property 'name', String, nullable: false
          c.property 'region', String, nullable: false
        end
        address_info_complex = s.add_complex_type(name: 'AddressInfo') do |c|
          c.property 'address', String
          c.property 'city', country_city_complex
        end
        person_gender_enum = s.add_enum_type(name: 'PersonGender') do |e|
          e.member 'Male'
          e.member 'Female'
          e.member 'Unknown'
        end
        person_entity = s.add_entity_type(name: 'Person') do |et|
          et.property_ref 'id', String
          et.property 'user_name', String, nullable: false
          et.property 'name', String
          et.property 'emails', [String], nullable: false
          et.property 'address_info', [address_info_complex], nullable: false
          et.property 'gender', person_gender_enum, nullable: false
          et.property 'concurrency', Integer, nullable: false
        end

        s.add_entity_set(name: 'People', url: 'People', entity_type: person_entity,
                         resolver: 'PeopleResolver')
      end
    end

    describe '#index_hash' do
      it do
        expect(EdmxSchema.index_hash(schema))
          .to eq({
                   '@odata.context': 'http://localhost/$metadata',
                   value: [{ kind: 'EntitySet', name: 'People', url: 'People' }]
                 })
      end
    end

    describe '#metadata_xml' do
      it 'works' do
        generated_xml = format_xml(EdmxSchema.metadata_xml(schema))
        expected_xml = format_xml(File.read("#{__dir__}/../metadata.xml"))
        expect(generated_xml).to eq(expected_xml)
      end
    end

    describe '#execute' do
      describe 'collection' do
        it do
          response = Oj.load(
            schema.execute('People', context: Context.new)
          )
          expect(response['@odata.context']).to eq('$metadata#People')
          expect(response['value'][0]).to eq(
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
          )
          expect(response['value'].size).to eq(1)
        end

        it do
          response = Oj.load(
            schema.execute('People', context: Context.new, query_options: { 'none' => 'true' })
          )
          expect(response['@odata.context']).to eq('$metadata#People')
          expect(response['value']).to be_empty
        end
      end

      describe 'count' do
        it do
          response = schema.execute('People/$count', context: Context.new)

          expect(response).to eq(1)
        end
      end

      describe 'individual' do
        it do
          json_string = schema.execute("People('1')", context: Context.new)
          response = Oj.load(json_string)
          expect(response).to eq(
            '@odata.context' => '$metadata#People/$entity',
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
            'concurrency' => 11
          )
        end
      end
    end
  end
end
