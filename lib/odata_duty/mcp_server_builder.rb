require 'mcp'
require 'odata_duty/mcp_input_schemas'

module OdataDuty
  module McpServerBuilder
    extend self

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
      define_tool(server, schema, :execute,
                  url_for: ->(_args) { endpoint.url },
                  name: "list_#{endpoint.name}",
                  description: "List #{endpoint.name} records", input_schema: input_schema)
    end

    def register_count_tool(server, schema, endpoint)
      input_schema = McpInputSchemas.count_input_schema(supports_search: endpoint.supports_search?)
      define_tool(server, schema, :execute,
                  url_for: ->(_args) { "#{endpoint.url}/$count" },
                  name: "count_#{endpoint.name}",
                  description: "Count #{endpoint.name} records", input_schema: input_schema)
    end

    def register_create_tool(server, schema, endpoint)
      define_tool(server, schema, :create,
                  url_for: ->(_args) { endpoint.url },
                  name: "create_#{endpoint.name}",
                  description: "Create a new #{endpoint.name} record",
                  input_schema: McpInputSchemas.create_input_schema(endpoint.entity_type))
    end

    def register_get_tool(server, schema, endpoint)
      define_tool(server, schema, :execute,
                  url_for: keyed_url_for(endpoint),
                  name: "get_#{endpoint.name}",
                  description: "Get a single #{endpoint.name} record by ID",
                  input_schema: McpInputSchemas.get_input_schema(endpoint.entity_type))
    end

    def register_key_tool(server, schema, endpoint, action, verb)
      input_schema = McpInputSchemas.public_send("#{action}_input_schema", endpoint.entity_type)
      define_tool(server, schema, action,
                  url_for: keyed_url_for(endpoint),
                  name: "#{action}_#{endpoint.name}",
                  description: "#{verb} #{endpoint.name} record", input_schema: input_schema)
    end

    # Builds the `<url>('<key>')` locator from the tool arguments. The dynamic `args[key]` lookup
    # has no mutation-testable equivalent (the key is always present, enforced by the SDK's
    # required-argument check), so this is the one MCP subject left on the .mutant.yml ignore list.
    def keyed_url_for(endpoint)
      key = endpoint.entity_type.property_refs.first.name
      ->(args) { "#{endpoint.url}('#{args[key]}')" }
    end

    # On the .mutant.yml ignore list: `server_context[:context]` has only equivalent mutants
    # (`[]` vs `fetch`/`dig`); the key is always present, so no public-API test distinguishes them.
    def define_tool(server, schema, action, url_for:, **tool_args)
      server.define_tool(**tool_args) do |server_context:, **args|
        McpServerBuilder.run_tool(action, url: url_for.call(args), schema: schema,
                                          context: server_context[:context],
                                          query_options: args.transform_keys(&:to_s))
      end
    end

    # On the .mutant.yml ignore list: `e.message` has only an equivalent mutant (`e`), since an
    # OdataDuty::Error renders identically to its message in the text content block.
    def run_tool(action, url:, schema:, context:, query_options:)
      result = Executor.public_send(action, url: url, context: context,
                                            query_options: query_options, schema: schema)
      MCP::Tool::Response.new([{ type: 'text', text: result.to_s }])
    rescue OdataDuty::Error => e
      MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
    end
  end
end
