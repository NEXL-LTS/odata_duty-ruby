require 'uri'

module OdataDuty
  MCP_SEARCH_DESCRIPTION = 'Search query using expressions with AND, OR, NOT operators'.freeze
  MCP_SEARCH_INPUT_SCHEMA = {
    'type' => 'object',
    'properties' => {
      '$search' => { 'type' => 'string', 'description' => MCP_SEARCH_DESCRIPTION }
    },
    'required' => ['$search']
  }.freeze

  MCP_CAPABILITIES = {
    'logging' => {}, 'prompts' => { 'listChanged' => false },
    'resources' => { 'subscribe' => false, 'listChanged' => false },
    'tools' => { 'listChanged' => false }
  }.freeze

  class MCPExecutor
    def self.handle(**)
      new(**).handle
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
      { 'protocolVersion' => '2024-11-05', 'capabilities' => MCP_CAPABILITIES,
        'serverInfo' => { 'name' => schema.title, 'version' => schema.version } }
    end

    def run_resources_read
      query_options = {}
      URI.decode_www_form(uri.query || '').each { |k, v| query_options[k] ||= v }
      Executor.execute(url: uri.path, context: @context,
                       query_options: query_options, schema: schema)
    end

    def all_resources
      schema.endpoints.flat_map { |endpoint| resources_for_endpoint(endpoint) }
    end

    def handle_resources_list
      { 'resources' => all_resources.select { |r| r.key?('uri') } }
    end

    def handle_resources_templates_list
      { 'resourceTemplates' => all_resources.select { |r| r.key?('uriTemplate') } }
    end

    def handle_tools_list
      search_tools = schema.endpoints.select(&:supports_search?).map { |ep| build_tool(ep) }
      create_tools = schema.endpoints.select(&:supports_create?).map { |ep| build_create_tool(ep) }

      { 'tools' => search_tools + create_tools }
    end

    def build_tool(endpoint)
      { 'name' => "search_#{endpoint.name}",
        'description' => "Search #{endpoint.name} using expressions with AND, OR, NOT operators",
        'inputSchema' => MCP_SEARCH_INPUT_SCHEMA }
    end

    def build_create_tool(endpoint)
      { 'name' => "create_#{endpoint.name}",
        'description' => "Create a new #{endpoint.name} record",
        'inputSchema' => create_input_schema(endpoint.entity_type) }
    end

    def create_input_schema(entity_type)
      properties = entity_type.properties.to_h { |p| [p.name.to_s, p.to_oas2] }
      required = entity_type.properties.reject(&:nullable).map { |p| p.name.to_s }
      { 'type' => 'object', 'properties' => properties, 'required' => required }
    end

    def handle_tools_call
      tool_name = request_hash['params']['name']
      query_options = request_hash['params']['arguments'] || {}
      endpoint = find_endpoint(tool_name[7..])

      if tool_name.start_with?('search_') && endpoint&.supports_search?
        run_tool(:execute, endpoint, query_options)
      elsif tool_name.start_with?('create_') && endpoint&.supports_create?
        run_tool(:create, endpoint, query_options)
      else
        raise "Unknown tool: #{tool_name}"
      end
    end

    def find_endpoint(endpoint_name)
      schema.endpoints.find { |ep| ep.name == endpoint_name }
    end

    def run_tool(action, endpoint, query_options)
      result = Executor.public_send(action, url: endpoint.url, context: context,
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
end
