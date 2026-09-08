require 'odata_duty/mcp_input_schemas'

module OdataDuty
  # Translates a `tools/call` argument hash into the query options Executor expects, undoing the
  # `odata_*` aliasing and array shapes McpInputSchemas advertises on the read tools.
  module McpToolArguments
    extend self

    # Inverse of McpInputSchemas::QUERY_OPTION_ALIASES: translates a tool call's `odata_*`
    # arguments back to their `$`-prefixed OData spelling before they reach Executor.
    QUERY_OPTION_SPELLINGS = McpInputSchemas::QUERY_OPTION_ALIASES.invert.freeze

    SELECT_OPTION = QUERY_OPTION_SPELLINGS.fetch(McpInputSchemas.alias_for('$select')).freeze

    # The `odata_*` → `$`-prefixed spellings for the aliases one tool's input schema declares as
    # query options, keyed off the schema's own property keys. McpInputSchemas keys entity
    # properties by symbol and query-option aliases by string, so an entity property literally
    # named `odata_skiptoken` — a `get_<Set>` tool's key, say — is not one of them.
    def spellings_for(input_schema_keys)
      QUERY_OPTION_SPELLINGS.slice(*input_schema_keys)
    end

    # The `odata_*` aliases only stand in for OData query options on read (`:execute`) tools —
    # `:create`/`:update`/`:delete` tools' arguments are property values, so a property literally
    # named e.g. `odata_select` must reach Executor unchanged, not get aliased to `$select`.
    def query_options_for(action, args, spellings)
      return args.transform_keys(&:to_s) unless action == :execute

      args.to_h do |key, value|
        name = key.to_s
        spelling = spellings.fetch(name, name)
        [spelling, query_option_value(spelling, value)]
      end
    end

    # A declared `odata_select` is advertised as an array of property names, so it needs joining
    # back to `$select`'s comma-separated OData spelling. Every other value is passed through as
    # given — including an `odata_select` a tool never declared (on a `count_<Set>`, say), which
    # is no more a query option than any other undeclared argument.
    def query_option_value(spelling, value)
      return value unless spelling == SELECT_OPTION

      value.join(',')
    end
  end
end
