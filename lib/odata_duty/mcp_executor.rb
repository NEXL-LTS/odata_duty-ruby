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
      method_name = :"handle_#{request_hash['method'].to_s.tr('/', '_')}"
      result = send(method_name)

      return nil if result.nil?

      Oj.dump('jsonrpc' => '2.0', 'id' => request_hash['id'], 'result' => result)
    end

    private

    def handle_notifications_initialized; end

    def handle_resources_read
      { 'contents' => [{ 'uri' => uri.path, 'mimeType' => 'application/json',
                         'text' => run_resources_read.to_s }] }
    end

    def handle_initialize
      {
        'protocolVersion' => '2024-11-05',
        'capabilities' => {
          'logging' => {}, 'prompts' => { 'listChanged' => false },
          'resources' => { 'subscribe' => false, 'listChanged' => false },
          'tools' => { 'listChanged' => false }
        },
        'serverInfo' => { 'name' => schema.title, 'version' => schema.version }
        # "instructions": "Optional instructions for the client"
      }
    end

    def run_resources_read
      query_options = CGI.parse(uri.query || '').transform_values(&:first)
      Executor.execute(url: uri.path, context: @context,
                       query_options: query_options, schema: schema)
    end

    def handle_resources_list
      resources_list = schema.endpoints.flat_map { |endpoint| resources_for_endpoint(endpoint) }
      { 'resources' => resources_list.select { |r| r.key?('uri') } }
    end

    def handle_resources_templates_list
      resources_list = schema.endpoints.flat_map { |endpoint| resources_for_endpoint(endpoint) }
      { 'resourceTemplates' => resources_list.select { |r| r.key?('uriTemplate') } }
    end

    def handle_tools_list
      tools = schema.endpoints.flat_map { |endpoint| tools_for_endpoint(endpoint) }
      { 'tools' => tools }
    end

    def tools_for_endpoint(endpoint)
      entity_name = endpoint.entity_type.name.downcase
      collection_name = endpoint.name.downcase

      tools = [
        {
          'name' => "get_#{entity_name}_by_id",
          'description' => "Get a specific #{endpoint.entity_type.name} by ID",
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'id' => {
                'type' => 'string',
                'description' => "#{endpoint.entity_type.name} ID"
              }
            },
            'required' => ['id']
          }
        },
        {
          'name' => "list_#{collection_name}",
          'description' => "List #{endpoint.name} with pagination",
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'top' => {
                'type' => 'integer',
                'description' => 'Number of records to return',
                'minimum' => 0
              },
              'skip' => {
                'type' => 'integer',
                'description' => 'Number of records to skip',
                'minimum' => 0
              }
            }
          }
        },
        {
          'name' => "count_#{collection_name}",
          'description' => "Count #{endpoint.name}",
          'inputSchema' => {
            'type' => 'object',
            'properties' => {}
          }
        }
      ]

      # Add search tool if endpoint supports search
      if endpoint.supports_search?
        tools << {
          'name' => "search_#{collection_name}",
          'description' => "Search #{endpoint.name} using expressions with AND, OR, NOT operators",
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              '$search' => {
                'type' => 'string',
                'description' => 'Search query using expressions with AND, OR, NOT operators'
              }
            },
            'required' => ['$search']
          }
        }
      end

      tools
    end

    def handle_tools_call
      tool_name = request_hash['params']['name']
      args = request_hash['params']['arguments'] || {}

      # Find matching endpoint
      endpoint = find_endpoint_for_tool(tool_name)
      raise "Unknown tool: #{tool_name}" unless endpoint

      # Execute the appropriate operation
      result = execute_tool(tool_name, endpoint, args)

      # Return MCP-compliant response
      { 'content' => [{ 'type' => 'text', 'text' => Oj.dump(result) }] }
    end

    def find_endpoint_for_tool(tool_name)
      schema.endpoints.find do |ep|
        entity_name = ep.entity_type.name.downcase
        collection_name = ep.name.downcase
        tool_name == "get_#{entity_name}_by_id" ||
          tool_name == "list_#{collection_name}" ||
          tool_name == "count_#{collection_name}" ||
          tool_name == "search_#{collection_name}"
      end
    end

    def execute_tool(tool_name, endpoint, args)
      entity_name = endpoint.entity_type.name.downcase
      collection_name = endpoint.name.downcase

      case tool_name
      when "get_#{entity_name}_by_id"
        id = args['id'].to_s
        url = "#{endpoint.url}('#{id}')"
        result = Executor.execute(url: url, context: context, query_options: {}, schema: schema)
        Oj.load(result)
      when "list_#{collection_name}"
        top = args['top'].to_i
        skip = args['skip'].to_i
        query_options = {}
        query_options['$top'] = top.to_s if top > 0
        query_options['$skip'] = skip.to_s if skip > 0
        result = Executor.execute(url: endpoint.url, context: context, query_options: query_options, schema: schema)
        Oj.load(result)
      when "count_#{collection_name}"
        url = "#{endpoint.url}/$count"
        Executor.execute(url: url, context: context, query_options: {}, schema: schema)
      when "search_#{collection_name}"
        query_options = { '$search' => args['$search'] }
        result = Executor.execute(url: endpoint.url, context: context, query_options: query_options, schema: schema)
        Oj.load(result)
      end
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
