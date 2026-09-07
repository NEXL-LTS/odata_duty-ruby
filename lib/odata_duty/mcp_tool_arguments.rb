require 'odata_duty/mcp_input_schemas'

module OdataDuty
  # Translates a `tools/call` argument hash into the query options Executor expects, undoing the
  # `odata_*` aliasing and array shapes McpInputSchemas advertises on the read tools.
  module McpToolArguments
    extend self

    # Inverse of McpInputSchemas::QUERY_OPTION_ALIASES: translates a tool call's `odata_*`
    # arguments back to their `$`-prefixed OData spelling before they reach Executor.
    QUERY_OPTION_SPELLINGS = McpInputSchemas::QUERY_OPTION_ALIASES.invert.freeze

    SELECT_ALIAS = McpInputSchemas.alias_for('$select')

    # The `odata_*` aliases only stand in for OData query options on read (`:execute`) tools —
    # `:create`/`:update`/`:delete` tools' arguments are property values, so a property literally
    # named e.g. `odata_select` must reach Executor unchanged, not get aliased to `$select`.
    def query_options_for(action, args)
      return args.transform_keys(&:to_s) unless action == :execute

      args.to_h do |key, value|
        name = key.to_s
        [QUERY_OPTION_SPELLINGS.fetch(name, name), query_option_value(name, value)]
      end
    end

    # `odata_select` is advertised as an array of property names, so it needs joining back to
    # `$select`'s comma-separated OData spelling. Every other value is passed through as given.
    def query_option_value(name, value)
      return value unless name == SELECT_ALIAS

      value.join(',')
    end
  end
end
