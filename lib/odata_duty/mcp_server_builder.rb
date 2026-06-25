require 'mcp'
require 'uri'
require 'odata_duty/mcp_input_schemas'

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
      schema.endpoints.each { |endpoint| register_endpoint_tools(server, schema, endpoint) }
      server
    end

    def register_endpoint_tools(server, schema, endpoint)
      register_search_tool(server, schema, endpoint) if endpoint.supports_search?
      register_create_tool(server, schema, endpoint) if endpoint.supports_create?
      register_update_tool(server, schema, endpoint) if endpoint.supports_update?
      register_delete_tool(server, schema, endpoint) if endpoint.supports_delete?
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
      result = Executor.execute(url: uri.path, context: context,
                                query_options: query_options, schema: schema)
      mime_type = uri.path.include?('/$count') ? 'text/plain' : 'application/json'
      [{ uri: uri_string, mimeType: mime_type, text: result.to_s }]
    rescue OdataDuty::Error => e
      [{ uri: uri_string, mimeType: 'text/plain', text: e.message.to_s }]
    end

    def register_search_tool(server, schema, endpoint)
      description = "Search #{endpoint.name} using expressions with AND, OR, NOT operators"
      define_tool(server, schema, endpoint, :execute,
                  name: "search_#{endpoint.name}", description: description,
                  input_schema: McpInputSchemas.search_input_schema)
    end

    def register_create_tool(server, schema, endpoint)
      define_tool(server, schema, endpoint, :create,
                  name: "create_#{endpoint.name}",
                  description: "Create a new #{endpoint.name} record",
                  input_schema: McpInputSchemas.create_input_schema(endpoint.entity_type))
    end

    def register_update_tool(server, schema, endpoint)
      register_key_tool(server, schema, endpoint, :update, 'Update an existing')
    end

    def register_delete_tool(server, schema, endpoint)
      register_key_tool(server, schema, endpoint, :delete, 'Delete an existing')
    end

    def register_key_tool(server, schema, endpoint, action, verb)
      key = endpoint.entity_type.property_refs.first.name.to_sym
      input_schema = McpInputSchemas.public_send("#{action}_input_schema", endpoint.entity_type)
      define_tool(server, schema, endpoint, action,
                  url_for: ->(args) { "#{endpoint.url}('#{args[key]}')" },
                  name: "#{action}_#{endpoint.name}",
                  description: "#{verb} #{endpoint.name} record", input_schema: input_schema)
    end

    def define_tool(server, schema, endpoint, action, url_for: nil, **tool_args)
      url_for ||= ->(_args) { endpoint.url }
      server.define_tool(**tool_args) do |server_context:, **args|
        McpServerBuilder.run_tool(action, url: url_for.call(args), schema: schema,
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
  end
end
