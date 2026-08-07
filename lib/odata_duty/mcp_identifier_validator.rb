module OdataDuty
  # Guards `McpServerBuilder`'s generated tool names and `input_schema` property keys against the
  # Anthropic Messages API's tool-schema identifier constraints, before a tool is registered on
  # the MCP server. Raises `InvalidMcpIdentifierError` on the first violation found.
  module McpIdentifierValidator
    extend self

    # Property keys additionally allow `.`.
    PROPERTY_KEY_REGEXP = /\A[a-zA-Z0-9_.-]{1,64}\z/
    TOOL_NAME_REGEXP = /\A[a-zA-Z0-9_-]{1,64}\z/

    def validate_tool_name!(name)
      return if name.match?(TOOL_NAME_REGEXP)

      raise InvalidMcpIdentifierError,
            "tool name \"#{name}\" is #{name.length} characters — MCP tool names must " \
            "match #{TOOL_NAME_REGEXP.inspect}"
    end

    def validate_properties!(endpoint, tool_name, input_schema)
      input_schema.fetch('properties').each_key do |key|
        next if key.to_s.match?(PROPERTY_KEY_REGEXP)

        raise InvalidMcpIdentifierError,
              "#{endpoint.entity_type.name} property \"#{key}\" cannot be used as an MCP tool " \
              "input key — it must match #{PROPERTY_KEY_REGEXP.inspect} (#{tool_name})"
      end
    end
  end
end
