require 'cgi'
require 'uri'

module OdataDuty
  # rubocop:disable Metrics/ClassLength
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
      tools = [
        tool_get_by_id(endpoint),
        tool_list(endpoint),
        tool_count(endpoint)
      ]
      tools << tool_search(endpoint) if endpoint.supports_search?
      tools
    end

    # rubocop:disable Metrics/MethodLength
    def tool_get_by_id(endpoint)
      entity_name = endpoint.entity_type.name.downcase
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
      }
    end

    def tool_list(endpoint)
      {
        'name' => "list_#{endpoint.name}",
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
      }
    end

    def tool_count(endpoint)
      {
        'name' => "count_#{endpoint.name}",
        'description' => "Count #{endpoint.name}",
        'inputSchema' => {
          'type' => 'object',
          'properties' => {}
        }
      }
    end

    def tool_search(endpoint)
      {
        'name' => "search_#{endpoint.name}",
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
    # rubocop:enable Metrics/MethodLength

    def handle_tools_call
      tool_name = request_hash['params']['name']
      args = request_hash['params']['arguments'] || {}

      # Find matching endpoint
      endpoint = find_endpoint_for_tool(tool_name)
      raise "Unknown tool: #{tool_name}" unless endpoint

      # Execute the appropriate operation and return parsed result directly
      execute_tool(tool_name, endpoint, args)
    end

    def find_endpoint_for_tool(tool_name)
      schema.endpoints.find do |ep|
        tool_names_for_endpoint(ep).include?(tool_name)
      end
    end

    def tool_names_for_endpoint(endpoint)
      entity_name = endpoint.entity_type.name.downcase
      collection_name = endpoint.name
      collection_name_lower = endpoint.name.downcase

      [
        "get_#{entity_name}_by_id",
        "list_#{collection_name}",
        "list_#{collection_name_lower}",
        "count_#{collection_name}",
        "count_#{collection_name_lower}",
        "search_#{collection_name}",
        "search_#{collection_name_lower}"
      ]
    end

    def execute_tool(tool_name, endpoint, args)
      entity_name = endpoint.entity_type.name.downcase
      collection_name = endpoint.name
      collection_name_lower = endpoint.name.downcase

      return exec_get_by_id(endpoint, args['id']) if tool_name == "get_#{entity_name}_by_id"

      if ["list_#{collection_name}", "list_#{collection_name_lower}"].include?(tool_name)
        return exec_list(endpoint, args['top'], args['skip'])
      end

      if ["count_#{collection_name}", "count_#{collection_name_lower}"].include?(tool_name)
        return exec_count(endpoint)
      end

      if ["search_#{collection_name}", "search_#{collection_name_lower}"].include?(tool_name)
        exec_search(endpoint, args['$search'])
      end
    end

    def exec_get_by_id(endpoint, id)
      url = "#{endpoint.url}('#{id}')"
      result = Executor.execute(url: url, context: context, query_options: {}, schema: schema)
      Oj.load(result)
    end

    def exec_list(endpoint, top, skip)
      query_options = {}
      query_options['$top'] = top.to_s if top.to_i.positive?
      query_options['$skip'] = skip.to_s if skip.to_i.positive?
      result = Executor.execute(url: endpoint.url, context: context,
                                query_options: query_options, schema: schema)
      Oj.load(result)
    end

    def exec_count(endpoint)
      url = "#{endpoint.url}/$count"
      Executor.execute(url: url, context: context, query_options: {}, schema: schema)
    end

    def exec_search(endpoint, search_query)
      query_options = { '$search' => search_query }
      result = Executor.execute(url: endpoint.url, context: context,
                                query_options: query_options, schema: schema)
      Oj.load(result)
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
  # rubocop:enable Metrics/ClassLength
end
