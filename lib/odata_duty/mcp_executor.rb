require 'cgi'
require 'uri'

module OdataDuty
  class MCPExecutor
    def self.handle(**kwargs)
      new(**kwargs).handle
    end

    attr_reader :request_hash, :schema, :context

    def initialize(request_hash:, schema:, context:)
      @request_hash = request_hash
      @schema = schema
      @context = context
    end

    def uri
      @uri ||= URI.parse(request_hash['params']['uri'])
    end

    def handle
      result = case request_hash['method']
               when 'initialize' then handle_initialize
               when 'resources/list' then handle_resources_list
               when 'resources/templates/list' then handle_resources_templates_list
               when 'resources/read'
                 { 'contents' => [{
                   'uri' => uri.path,
                   'mimeType' => 'application/json',
                   'text' => handle_resources_read.to_s
                 }] }
               end

      return nil if result.nil?

      Oj.dump('jsonrpc' => '2.0', 'id' => request_hash['id'], 'result' => result)
    end

    private

    def handle_initialize
      {
        'protocolVersion' => '2024-11-05',
        'capabilities' => {
          'logging' => {},
          'prompts' => { 'listChanged' => false },
          'resources' => { 'subscribe' => false, 'listChanged' => false },
          'tools' => { 'listChanged' => false }
        },
        'serverInfo' => {
          'name' => schema.title,
          'version' => schema.version
        }
        # "instructions": "Optional instructions for the client"
      }
    end

    def handle_resources_read
      query_options = CGI.parse(uri.query || '').transform_values(&:first)
      Executor.execute(url: uri.path,
                       context: @context,
                       query_options: query_options,
                       schema: schema)
    end

    def handle_resources_list
      resources_list = schema.endpoints.flat_map { |endpoint| resources_for_endpoint(endpoint) }
      { 'resources' => resources_list.select { |r| r.key?('uri') } }
    end

    def handle_resources_templates_list
      resources_list = schema.endpoints.flat_map { |endpoint| resources_for_endpoint(endpoint) }
      { 'resourceTemplates' => resources_list.select { |r| r.key?('uriTemplate') } }
    end

    def resources_for_endpoint(endpoint)
      name = endpoint.name
      [{ 'uriTemplate' => "#{endpoint.url}('{id}')",
         'name' => endpoint.entity_type.name,
         'description' => "Retrieve a specific #{endpoint.entity_type.name} record by ID",
         'mimeType' => 'application/json' },
       { 'uriTemplate' => "#{endpoint.url}?$top={top}&$skip={skip}",
         'name' => "Paginated #{name} Collection",
         'description' => "Retrieve paginated #{name} records",
         'mimeType' => 'application/json' },
       { 'uri' => "#{endpoint.url}/$count",
         'name' => "#{name} Count",
         'description' => "Get a count of #{name} records",
         'mimeType' => 'text/plain' }]
    end
  end
end
