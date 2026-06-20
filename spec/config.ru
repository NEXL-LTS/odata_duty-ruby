require 'rack'
require 'json'
require_relative '../lib/odata_duty'

# Run :
# `npx @modelcontextprotocol/inspector@0.14.3 -e PORT=9292`
# `bundle exec rerun -- bundle exec rackup spec/config.ru`
# MCP is served over a single Streamable HTTP endpoint at POST/GET/DELETE /mcp.

class TestPersonResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, user_name: 'john_doe', name: 'John Doe', emails: ['john@example.com']),
      OpenStruct.new(id: 2, user_name: 'jane_smith', name: 'Jane Smith',
                     emails: ['jane@example.com', 'j.smith@work.com'])
    ]
  end

  def od_search(search_expression)
    if search_expression.or?
      od_search_or(search_expression)
    else
      od_search_and(search_expression)
    end
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |record| record.send(property_name) == value }
  end

  def od_filter_ne(property_name, value)
    @records = @records.reject { |record| record.send(property_name) == value }
  end

  def count
    @records.count
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id.to_i }
  end

  private

  # rubocop:disable Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
  def filter_records_by_terms(search_expression, accumulate: false)
    result_records = accumulate ? [] : @records

    search_expression.terms.each do |term|
      matches = @records.select do |record|
        match_found = record.to_h.values.any? { |v| v.to_s.downcase.include?(term.value.downcase) }
        term.not? ? !match_found : match_found
      end

      if accumulate
        result_records += matches
      else
        result_records &= matches
      end
    end

    accumulate ? result_records.uniq { |r| r['id'] } : result_records
  end
  # rubocop:enable Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity

  def od_search_or(search_expression)
    @records = filter_records_by_terms(search_expression, accumulate: true)
  end

  def od_search_and(search_expression)
    @records = filter_records_by_terms(search_expression, accumulate: false)
  end
end

# rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Layout/LineLength
class TestApiApp
  def initialize
    @schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                             scheme: 'http', base_path: '/api') do |s|
      s.title = 'Test OData API'
      s.version = '1.0.0'
      person_entity = s.add_entity_type(name: 'Person') do |et|
        et.property_ref 'id', Integer
        et.property 'user_name', String, nullable: false
        et.property 'name', String
        et.property 'emails', [String], nullable: false
      end
      s.add_entity_set(url: 'People', entity_type: person_entity,
                       resolver: 'TestPersonResolver')
    end
    # Stateless Streamable HTTP keeps this demo self-contained (no session storage).
    @mcp_server = @schema.to_mcp_server
    @mcp_server.server_context = { context: self }
    @mcp_transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      @mcp_server, stateless: true, enable_json_response: true
    )
  end

  def call(env)
    request = Rack::Request.new(env)

    case request.path_info
    when '/mcp'
      @mcp_transport.handle_request(request)
    when '/api'
      [200, { 'content-type' => 'application/json' }, [JSON.generate(
        OdataDuty::EdmxSchema.index_hash(@schema)
      )]]

    when '/api/$metadata'
      [200, { 'content-type' => 'application/xml' }, [
        OdataDuty::EdmxSchema.metadata_xml(@schema)
      ]]

    when '/api/$oas2'
      [200, { 'content-type' => 'application/json' }, [JSON.generate(
        OdataDuty::OAS2.build_json(@schema)
      )]]

    else
      if request.path_info.start_with?('/api/')
        url = request.path_info.sub('/api/', '')
        query_options = request.params

        begin
          case request.request_method
          when 'GET'
            result = @schema.execute(url, context: self, query_options: query_options)
            [200, { 'content-type' => 'application/json' }, [JSON.generate(result)]]
          when 'POST'
            result = @schema.create(url, context: self, query_options: query_options)
            [201, { 'content-type' => 'application/json' }, [JSON.generate(result)]]
          else
            [405, { 'content-type' => 'application/json' }, [JSON.generate({
                                                                             error: 'Method Not Allowed',
                                                                             message: "#{request.request_method} not supported"
                                                                           })]]
          end
        rescue StandardError => e
          [500, { 'content-type' => 'application/json' }, [JSON.generate({
                                                                           error: 'Internal Server Error',
                                                                           message: e.message
                                                                         })]]
        end
      else
        [404, { 'content-type' => 'application/json' }, [JSON.generate({
                                                                         error: 'Not Found',
                                                                         path: request.path_info
                                                                       })]]
      end
    end
  end
end
# rubocop:enable Metrics/MethodLength,Metrics/CyclomaticComplexity,Layout/LineLength

run TestApiApp.new
