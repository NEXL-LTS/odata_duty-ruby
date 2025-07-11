require 'rack'
require 'json'
require_relative '../lib/odata_duty'

# Run :
# `npx @modelcontextprotocol/inspector@0.14.3 -e PORT=9292`
# `bundle exec rerun -- bundle exec rackup spec/config.ru`

class TestPersonResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [
      OpenStruct.new(id: 1, user_name: 'john_doe', name: 'John Doe', emails: ['john@example.com']),
      OpenStruct.new(id: 2, user_name: 'jane_smith', name: 'Jane Smith',
                     emails: ['jane@example.com', 'j.smith@work.com'])
    ]
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
end

# rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Layout/LineLength
class TestApiApp
  def initialize
    @schema = OdataDuty::SchemaBuilder.build(namespace: 'TestSpace', host: 'localhost:9292',
                                             scheme: 'http', base_path: '/api') do |s|
      s.title = 'Test OData API'
      s.version = '1.0.0'
      person_entity = s.add_entity_type(name: 'Person') do |et|
        et.property_ref 'id', String
        et.property 'user_name', String, nullable: false
        et.property 'name', String
        et.property 'emails', [String], nullable: false
      end
      s.add_entity_set(url: 'People', entity_type: person_entity,
                       resolver: 'TestPersonResolver')
    end
    @queue = Queue.new
  end

  def call(env)
    request = Rack::Request.new(env)

    case request.path_info
    when '/events'
      sse_response(env)
    when '/jsonrpc'
      data = request.body.read
      puts "Received JSON-RPC data: #{data.inspect}"
      response = @schema.handle_jsonrpc(JSON.parse(data), context: self)
      @queue << { event: 'message', data: response } if response
      [202, { 'content-type' => 'application/json' }, [JSON.generate({ status: 'accepted' })]]
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

  private

  def sse_response(_env)
    body = proc do |stream|
      @queue << { event: 'endpoint', data: '/jsonrpc' }
      Thread.new do
        loop do
          sleep 10
          @queue << { event: 'ping', data: Time.now.to_s }
        end
      end
      loop do
        message = @queue.pop
        puts "Sending SSE message: #{message.inspect}"
        stream.write "event: #{message[:event]}\n"
        data = message[:data].is_a?(String) ? message[:data] : JSON.generate(message[:data])
        stream.write "data: #{data}\n\n"
      end
    ensure
      stream.close
    end

    [200, { 'content-type' => 'text/event-stream' }, body]
  end
end
# rubocop:enable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Layout/LineLength

run TestApiApp.new
