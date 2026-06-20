require 'spec_helper'

class PeopleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = if context.query_options['none'] == 'true'
                 []
               else
                 Person.all
               end
  end

  def od_top(value)
    @od_top = value.to_i
  end

  def od_skip(value)
    @od_skip = value.to_i
  end

  def od_skiptoken(value)
    @od_skiptoken = value
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

module OdataDuty
  RSpec.describe SchemaBuilder do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', scheme: 'http', host: 'localhost',
                          base_path: '/') do |s|
        s.version = '1.2.3'
        s.title = 'This is a sample OData service.'
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
        expect(schema.index_hash)
          .to eq({
                   '@odata.context': 'http://localhost/$metadata',
                   value: [{ kind: 'EntitySet', name: 'People', url: 'People' }]
                 })
      end
    end

    describe '#metadata_xml' do
      it 'works' do
        generated_xml = format_xml(schema.metadata_xml)
        expected_xml = format_xml(File.read("#{__dir__}/../metadata.xml"))
        expect(generated_xml).to eq(expected_xml)
      end
    end

    EXPECTED_DOC = Oj.load(File.read("#{__dir__}/../oas_2.json"))

    describe '#oas_2' do
      let(:json) { OAS2.build_json(schema, context: Context.new) }

      it do
        s = %w[swagger info host schemes basePath]
        generated_json = json.slice(*s)
        expect(generated_json).to eq(EXPECTED_DOC.slice(*s))
      end

      EXPECTED_DOC.fetch('paths').each do |path, value|
        describe "paths #{path} get" do
          it do
            generated_json = json.dig('paths', path, 'get')
            value['get'].each do |k, v|
              if v.is_a?(Array)
                expect(generated_json[k]).to match_array(v)
              else
                expect(generated_json[k]).to eq(v)
              end
            end
            expect(generated_json).to eq(value['get'])
          end
        end
      end

      EXPECTED_DOC.fetch('definitions').each do |path, value|
        describe "definitions #{path}" do
          it do
            generated_json = json.dig('definitions', path)
            expect(generated_json).to eq(value)
          end
        end
      end
    end

    describe '#execute' do
      describe 'collection' do
        it do
          response = Oj.load(
            schema.execute('People', context: Context.new)
          )
          expect(response['@odata.context']).to eq('http://localhost/$metadata#People')
          expect(response['value'][0]).to eq(
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
          )
          expect(response['value'].size).to eq(1)
        end

        it do
          response = Oj.load(
            schema.execute('People', context: Context.new, query_options: { 'none' => 'true' })
          )
          expect(response['@odata.context']).to eq('http://localhost/$metadata#People')
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
            '@odata.context' => 'http://localhost/$metadata#People/$entity',
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
            'concurrency' => 11
          )
        end
      end
    end

    describe 'mcp' do
      let(:mcp_server) do
        server = schema.to_mcp_server
        server.server_context = { context: Context.new }
        server
      end

      def call(payload)
        Oj.load(mcp_server.handle_json(Oj.dump(payload)))
      end

      describe 'initialize' do
        let(:server_caps) { { 'tools' => {}, 'resources' => {} } }

        let(:request_payload) do
          {
            'jsonrpc' => '2.0',
            'id' => 'init-444',
            'method' => 'initialize',
            'params' => {
              'protocolVersion' => protocol_version,
              'capabilities' => { 'roots' => {}, 'sampling' => {} },
              'clientInfo' => { 'name' => 'RSpecClient', 'version' => '0.0.1' }
            }
          }
        end

        describe 'successful initialize' do
          let(:protocol_version) { '2024-11-05' }

          it 'negotiates the version and echoes capabilities and serverInfo' do
            response = Oj.load(schema.to_mcp_server.handle_json(Oj.dump(request_payload)))

            expect(response).to eq(
              'jsonrpc' => '2.0',
              'id' => 'init-444',
              'result' => {
                'protocolVersion' => '2024-11-05',
                'capabilities' => server_caps,
                'serverInfo' => { 'name' => 'This is a sample OData service.',
                                  'version' => '1.2.3' }
              }
            )
          end
        end

        describe 'unsupported protocol version' do
          let(:protocol_version) { '1999-01-01' }

          it 'falls back to the latest supported version' do
            response = Oj.load(schema.to_mcp_server.handle_json(Oj.dump(request_payload)))

            expect(response['result']['protocolVersion']).to eq('2025-11-25')
          end
        end
      end

      describe 'unknown method' do
        let(:request_payload) do
          { 'jsonrpc' => '2.0', 'id' => 'u-1', 'method' => 'does/not/exist', 'params' => {} }
        end

        it 'returns a -32601 error' do
          response = Oj.load(schema.to_mcp_server.handle_json(Oj.dump(request_payload)))

          expect(response['error']['code']).to eq(-32_601)
        end
      end

      describe 'notifications/initialized' do
        let(:request_payload) do
          { 'jsonrpc' => '2.0', 'method' => 'notifications/initialized', 'params' => {} }
        end

        it 'returns an empty response' do
          expect(schema.to_mcp_server.handle_json(Oj.dump(request_payload))).to be_nil
        end
      end

      describe 'resources/list' do
        let(:request_payload) do
          {
            'jsonrpc' => '2.0',
            'method' => 'resources/list',
            'params' => {},
            'id' => 'req-5'
          }
        end

        let(:expected) do
          {
            'jsonrpc' => '2.0',
            'id' => 'req-5',
            'result' => {
              'resources' => [
                {
                  'uri' => 'People/$count',
                  'name' => 'People Count',
                  'description' => 'Get a count of People records',
                  'mimeType' => 'text/plain'
                }
              ]
            }
          }
        end

        it 'returns direct resources' do
          actual = call(request_payload)
          actual_indexed = actual['result']['resources'].to_h { |r| [r['uri'], r] }
          expected_indexed = expected['result']['resources'].to_h { |r| [r['uri'], r] }
          expect(actual_indexed.keys).to match_array(expected_indexed.keys)
          actual_indexed.each_key do |key|
            expect(actual_indexed[key]).to eq(expected_indexed[key])
          end
        end
      end

      describe 'resources/templates/list' do
        let(:request_payload) do
          {
            'jsonrpc' => '2.0',
            'method' => 'resources/templates/list',
            'params' => {},
            'id' => 'req-5'
          }
        end

        let(:expected) do
          {
            'jsonrpc' => '2.0',
            'id' => 'req-5',
            'result' => {
              'resourceTemplates' => [
                {
                  'uriTemplate' => 'People(\'{id}\')',
                  'name' => 'Person',
                  'description' => 'Retrieve a specific Person record by ID',
                  'mimeType' => 'application/json'
                },
                {
                  'uriTemplate' => 'People?$top={top}&$skip={skip}',
                  'name' => 'Paginated People Collection',
                  'description' => 'Retrieve paginated People records',
                  'mimeType' => 'application/json'
                }
              ]
            }
          }
        end

        it 'returns resource templates' do
          actual = call(request_payload)

          actual_indexed = actual['result']['resourceTemplates'].to_h { |r| [r['uriTemplate'], r] }
          expected_indexed = expected['result']['resourceTemplates'].to_h do |r|
            [r['uriTemplate'], r]
          end
          expect(actual_indexed.keys).to match_array(expected_indexed.keys)
          actual_indexed.each_key do |key|
            expect(actual_indexed[key]).to eq(expected_indexed[key])
          end
        end
      end

      describe 'resources/read' do
        let(:request_payload) do
          {
            'jsonrpc' => '2.0',
            'method' => 'resources/read',
            'params' => { 'uri' => "People('1')" },
            'id' => 'req-6'
          }
        end

        let(:expected_response) do
          {
            'jsonrpc' => '2.0',
            'id' => 'req-6',
            'result' => {
              'contents' => [
                {
                  'uri' => "People('1')",
                  'mimeType' => 'application/json',
                  'text' => Oj.dump(
                    'id' => '1',
                    'user_name' => 'user1',
                    'name' => 'User',
                    'emails' => ['user@email.com'],
                    'address_info' => [
                      {
                        'address' => 'address',
                        'city' => {
                          'country_region' => 'country',
                          'name' => 'name',
                          'region' => 'region'
                        }
                      }
                    ],
                    'gender' => 'Male',
                    'concurrency' => 11,
                    '@odata.id' => 'http://localhost/People(\'1\')',
                    '@odata.context' => 'http://localhost/$metadata#People/$entity'
                  )
                }
              ]
            }
          }
        end

        it 'retrieves a specific resource successfully' do
          actual_response = call(request_payload)
          expect(actual_response.keys).to match_array(expected_response.keys)
          actual_contents = actual_response['result']['contents'][0]
          expected_contents = expected_response['result']['contents'][0]
          expect(actual_contents.keys).to match_array(expected_contents.keys)
          expect(Oj.load(actual_contents['text'])).to eq(Oj.load(expected_contents['text']))
          expect(actual_contents).to eq(expected_contents)
        end
      end
    end
  end
end
