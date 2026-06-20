require 'mcp'

module OdataDuty
  module McpServerBuilder
    module_function

    def build(schema)
      server = MCP::Server.new(
        name: schema.title,
        version: schema.version,
        capabilities: { tools: {}, resources: {} }
      )
      schema.endpoints.each do |endpoint|
        register_search_tool(server, schema, endpoint) if endpoint.supports_search?
        register_create_tool(server, schema, endpoint) if endpoint.supports_create?
      end
      server
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
