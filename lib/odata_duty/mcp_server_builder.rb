require 'mcp'
require 'uri'

module OdataDuty
  module McpServerBuilder
    module_function

    def build(schema)
      server = MCP::Server.new(
        name: schema.title,
        version: schema.version,
        capabilities: { tools: {}, resources: {} },
        resources: direct_resources(schema),
        resource_templates: resource_templates(schema)
      )
      register_resources_read(server, schema)
      schema.endpoints.each do |endpoint|
        register_search_tool(server, schema, endpoint) if endpoint.supports_search?
        register_create_tool(server, schema, endpoint) if endpoint.supports_create?
      end
      server
    end

    def direct_resources(schema)
      schema.endpoints.map { |endpoint| count_resource(endpoint) }
    end

    def resource_templates(schema)
      schema.endpoints.flat_map { |endpoint| templates_for_endpoint(endpoint) }
    end

    def count_resource(endpoint)
      MCP::Resource.new(uri: "#{endpoint.url}/$count", name: "#{endpoint.name} Count",
                        description: "Get a count of #{endpoint.name} records",
                        mime_type: 'text/plain')
    end

    def templates_for_endpoint(endpoint)
      type_name = endpoint.entity_type.name
      [MCP::ResourceTemplate.new(
        uri_template: "#{endpoint.url}('{id}')", name: type_name,
        description: "Retrieve a specific #{type_name} record by ID", mime_type: 'application/json'
      ),
       MCP::ResourceTemplate.new(
         uri_template: "#{endpoint.url}?$top={top}&$skip={skip}",
         name: "Paginated #{endpoint.name} Collection",
         description: "Retrieve paginated #{endpoint.name} records", mime_type: 'application/json'
       )]
    end

    def register_resources_read(server, schema)
      server.resources_read_handler do |params, server_context:|
        McpServerBuilder.read_resource(params[:uri], schema, server_context[:context])
      end
    end

    def read_resource(uri_string, schema, context)
      uri = URI.parse(uri_string)
      query_options = {}
      URI.decode_www_form(uri.query || '').each { |k, v| query_options[k] ||= v }
      text = Executor.execute(url: uri.path, context: context,
                              query_options: query_options, schema: schema)
      [{ uri: uri_string, mimeType: 'application/json', text: text }]
    rescue OdataDuty::Error => e
      [{ uri: uri_string, mimeType: 'application/json', text: e.message }]
    end

    def register_search_tool(server, schema, endpoint)
      description = "Search #{endpoint.name} using expressions with AND, OR, NOT operators"
      define_tool(server, schema, endpoint, :execute,
                  name: "search_#{endpoint.name}", description: description,
                  input_schema: search_input_schema)
    end

    def register_create_tool(server, schema, endpoint)
      define_tool(server, schema, endpoint, :create,
                  name: "create_#{endpoint.name}",
                  description: "Create a new #{endpoint.name} record",
                  input_schema: create_input_schema(endpoint.entity_type))
    end

    def define_tool(server, schema, endpoint, action, **tool_args)
      url = endpoint.url
      server.define_tool(**tool_args) do |server_context:, **args|
        McpServerBuilder.run_tool(action, url: url, schema: schema,
                                          context: server_context[:context],
                                          query_options: args.transform_keys(&:to_s))
      end
    end

    def run_tool(action, url:, schema:, context:, query_options:)
      json = Executor.public_send(action, url: url, context: context,
                                          query_options: query_options, schema: schema)
      MCP::Tool::Response.new([{ type: 'text', text: json }])
    rescue OdataDuty::Error => e
      MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
    end

    def search_input_schema
      { 'type' => 'object',
        'properties' => { '$search' => {
          'type' => 'string',
          'description' => 'Search query using expressions with AND, OR, NOT operators'
        } },
        'required' => ['$search'] }
    end

    def create_input_schema(entity_type)
      properties = entity_type.properties.to_h { |p| [p.name.to_s, p.to_oas2] }
      required = entity_type.properties.reject(&:nullable).map { |p| p.name.to_s }
      { 'type' => 'object', 'properties' => properties, 'required' => required }
    end
  end
end
