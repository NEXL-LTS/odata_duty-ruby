require 'mcp'
require 'odata_duty/mcp_input_schemas'

module OdataDuty
  module McpServerBuilder
    module_function

    def build(schema)
      server = MCP::Server.new(
        name: schema.title,
        version: schema.version,
        capabilities: { tools: {} }
      )
      schema.endpoints.each { |endpoint| register_endpoint_tools(server, schema, endpoint) }
      server
    end

    def register_endpoint_tools(server, schema, endpoint)
      register_collection_tools(server, schema, endpoint) if endpoint.supports_collection?
      register_get_tool(server, schema, endpoint) if endpoint.supports_individual?
      register_create_tool(server, schema, endpoint) if endpoint.supports_create?
      register_update_tool(server, schema, endpoint) if endpoint.supports_update?
      register_delete_tool(server, schema, endpoint) if endpoint.supports_delete?
    end

    def register_collection_tools(server, schema, endpoint)
      register_list_tool(server, schema, endpoint)
      register_count_tool(server, schema, endpoint) if endpoint.supports_count?
    end

    def register_update_tool(server, schema, endpoint)
      register_key_tool(server, schema, endpoint, :update, 'Update an existing')
    end

    def register_delete_tool(server, schema, endpoint)
      register_key_tool(server, schema, endpoint, :delete, 'Delete an existing')
    end

    def register_list_tool(server, schema, endpoint)
      input_schema = McpInputSchemas.list_input_schema(supports_search: endpoint.supports_search?)
      define_tool(server, schema, endpoint, :execute,
                  name: "list_#{endpoint.name}",
                  description: "List #{endpoint.name} records", input_schema: input_schema)
    end

    def register_count_tool(server, schema, endpoint)
      input_schema = McpInputSchemas.count_input_schema(supports_search: endpoint.supports_search?)
      define_tool(server, schema, endpoint, :execute,
                  url_for: ->(_args) { "#{endpoint.url}/$count" },
                  name: "count_#{endpoint.name}",
                  description: "Count #{endpoint.name} records", input_schema: input_schema)
    end

    def register_create_tool(server, schema, endpoint)
      define_tool(server, schema, endpoint, :create,
                  name: "create_#{endpoint.name}",
                  description: "Create a new #{endpoint.name} record",
                  input_schema: McpInputSchemas.create_input_schema(endpoint.entity_type))
    end

    def register_get_tool(server, schema, endpoint)
      key = endpoint.entity_type.property_refs.first.name.to_sym
      define_tool(server, schema, endpoint, :execute,
                  url_for: ->(args) { "#{endpoint.url}('#{args[key]}')" },
                  name: "get_#{endpoint.name}",
                  description: "Get a single #{endpoint.name} record by ID",
                  input_schema: McpInputSchemas.get_input_schema(endpoint.entity_type))
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
      result = Executor.public_send(action, url: url, context: context,
                                            query_options: query_options, schema: schema)
      MCP::Tool::Response.new([{ type: 'text', text: result.to_s }])
    rescue OdataDuty::Error => e
      MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
    end
  end
end
