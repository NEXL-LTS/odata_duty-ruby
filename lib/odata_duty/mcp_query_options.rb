module OdataDuty
  # Argument definitions for the `odata_*` query-option keys `McpInputSchemas` advertises on the
  # read tools, keyed by their `$`-prefixed OData spelling. Split out of `McpInputSchemas` so the
  # `$select` shape has one definition shared by the gated list/count tables and `get_`.
  module McpQueryOptions
    extend self

    FILTER_DESCRIPTION =
      'OData $filter expression; see the service instructions for the grammar. Filtering is ' \
      'supported for this entity set, but not every property or operator combination is ' \
      'necessarily implemented — an unsupported combination returns an error rather than an ' \
      'empty result. Property names are listed under odata_select. ' \
      "Example: user_name eq 'Alice'".freeze

    SELECT_DESCRIPTION = 'Properties to return; omit for all.'.freeze

    SEARCH_DESCRIPTION =
      'Free-text $search expression; terms combined with AND, OR, NOT. Parenthesised groups ' \
      'are not supported.'.freeze

    TOP_DESCRIPTION = 'Maximum number of records to return.'.freeze

    SKIP_DESCRIPTION = 'Number of records to skip before returning results.'.freeze

    SKIPTOKEN_DESCRIPTION =
      'Continuation token for the next page. Take it from the $skiptoken query parameter of a ' \
      "prior response's @odata.nextLink.".freeze

    def definitions(entity_type)
      {
        '$filter' => string_option(FILTER_DESCRIPTION),
        '$select' => select_option(entity_type),
        '$search' => string_option(SEARCH_DESCRIPTION),
        '$top' => integer_option(TOP_DESCRIPTION),
        '$skip' => integer_option(SKIP_DESCRIPTION),
        '$skiptoken' => string_option(SKIPTOKEN_DESCRIPTION)
      }
    end

    # An array of property names rather than OData's comma-separated string, so the `enum` can
    # advertise exactly which names are selectable and the MCP SDK rejects the rest before the
    # tool handler runs. McpToolArguments joins the array back to `$select`'s OData spelling.
    def select_option(entity_type)
      names = entity_type.properties.map { |property| property.name.to_s }
      { 'type' => 'array', 'description' => SELECT_DESCRIPTION,
        'items' => { 'type' => 'string', 'enum' => names } }
    end

    def string_option(description)
      { 'type' => 'string', 'description' => description }
    end

    # `minimum` lets the MCP SDK reject a negative paging argument against the tool schema
    # before the handler runs, where over REST it reaches Executor's InvalidQueryOptionError.
    def integer_option(description)
      { 'type' => 'integer', 'minimum' => 0, 'description' => description }
    end
  end
end
