module OdataDuty
  # Builds the MCP server `instructions` document: the schema's own description followed by a
  # description of the OData dialect the generated tools actually speak. A per-option line is
  # included only when at least one entity set in the schema supports that query option, so the
  # document never advertises a capability no tool exposes.
  module McpInstructions
    extend self

    INTRO = 'This service exposes a subset of OData v4. Query options are passed to tools as ' \
            '`odata_*` arguments (e.g. `odata_filter` is OData `$filter`).'.freeze

    FILTER_LINE = '$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ' \
                  'ne, gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with ' \
                  '`or` is not supported, nor is parenthesised grouping. Functions (contains, ' \
                  'startswith, tolower, …), arithmetic and `not` are not supported. String ' \
                  'literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO ' \
                  '8601 (2024-01-31, 2024-01-31T00:00:00+00:00).'.freeze

    SEARCH_LINE = '$search: terms combined with AND, OR, NOT. Parenthesised groups are not ' \
                  'supported.'.freeze

    PAGING_LINE = 'Paging: pass odata_skiptoken with the $skiptoken value from a prior ' \
                  "response's @odata.nextLink.".freeze

    UNSUPPORTED_LINE = '$orderby, $expand, $apply, $compute and $count=true are not ' \
                       'supported.'.freeze

    CLOSING = 'Each tool advertises only the query options its entity set supports.'.freeze

    # `[line, capability predicate]` in document order; each line is included only when some
    # endpoint answers true to its predicate.
    OPTION_LINES = [
      [FILTER_LINE, :supports_filter?],
      [SEARCH_LINE, :supports_search?],
      [PAGING_LINE, :supports_skiptoken?]
    ].freeze

    def build(schema)
      [schema.description, dialect(schema)].compact.join("\n\n")
    end

    def dialect(schema)
      [INTRO, option_lines(schema).join("\n"), CLOSING].join("\n\n")
    end

    def option_lines(schema)
      supported = OPTION_LINES.filter_map do |line, predicate|
        line if schema.endpoints.any? { |endpoint| endpoint.public_send(predicate) }
      end
      supported + [UNSUPPORTED_LINE]
    end
  end
end
