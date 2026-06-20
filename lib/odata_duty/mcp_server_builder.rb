require 'mcp'

module OdataDuty
  module McpServerBuilder
    module_function

    def build(schema)
      MCP::Server.new(
        name: schema.title,
        version: schema.version,
        capabilities: { tools: {}, resources: {} }
      )
    end
  end
end
