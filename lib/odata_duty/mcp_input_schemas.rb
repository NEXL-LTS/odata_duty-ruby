module OdataDuty
  module McpInputSchemas
    extend self

    # Property names are used as-is (symbols) for keys/required and the root `type: object` is
    # omitted; the MCP SDK normalizes the keys and supplies the root type default.

    # `$`-prefixed OData system query options are not valid Anthropic tool-schema property keys
    # (`^[a-zA-Z0-9_.-]{1,64}$`), so tool schemas expose these `odata_*` aliases instead.
    # McpServerBuilder uses the same mapping (inverted) to translate `tools/call` arguments back.
    QUERY_OPTION_ALIASES = {
      '$filter' => 'odata_filter',
      '$select' => 'odata_select',
      '$search' => 'odata_search',
      '$top' => 'odata_top',
      '$skip' => 'odata_skip',
      '$skiptoken' => 'odata_skiptoken'
    }.freeze

    UNGATED = nil

    LIST_QUERY_OPTIONS = [
      ['$filter', :supports_filter?, 'string', 'OData $filter expression'],
      ['$select', UNGATED, 'string', 'Comma-separated properties to return'],
      ['$search', :supports_search?, 'string', 'Search expression (AND, OR, NOT)'],
      ['$top', :supports_top?, 'integer', 'Max records to return'],
      ['$skip', :supports_skip?, 'integer', 'Records to skip'],
      ['$skiptoken', :supports_skiptoken?, 'string']
    ].freeze

    COUNT_QUERY_OPTIONS = [
      ['$filter', :supports_filter?, 'string'],
      ['$search', :supports_search?, 'string']
    ].freeze

    def count_input_schema(endpoint)
      { 'properties' => supported_query_options(COUNT_QUERY_OPTIONS, endpoint), 'required' => [] }
    end

    def list_input_schema(endpoint)
      { 'properties' => supported_query_options(LIST_QUERY_OPTIONS, endpoint), 'required' => [] }
    end

    def supported_query_options(definitions, endpoint)
      definitions.each_with_object({}) do |(key, predicate, type, description), properties|
        next if predicate && !endpoint.public_send(predicate)

        properties[alias_for(key)] = query_option(type, description)
      end
    end

    # Raises when an entity property is literally named like a reserved `odata_*` alias and
    # would silently overwrite (or be overwritten by) the reserved query-option key in the same
    # `properties` hash — see McpServerBuilder's tool-name/property-key validation.
    def add_alias!(properties, entity_type, query_option_key, value, tool_name:)
      key = alias_for(query_option_key)
      if properties.keys.map(&:to_s).include?(key)
        raise InvalidMcpIdentifierError,
              "#{entity_type.name} property \"#{key}\" collides with the reserved #{key} " \
              "query-option key in the #{tool_name} tool input schema"
      end

      properties[key] = value
    end

    def create_input_schema(entity_type)
      writable = entity_type.properties.select(&:settable_on_create?)
      properties = writable.to_h { |p| [p.name, p.to_oas2] }
      required = writable.reject(&:nullable).map(&:name)
      { 'properties' => properties, 'required' => required }
    end

    def update_input_schema(entity_type)
      key = entity_type.property_refs.first
      writable = entity_type.properties.select(&:settable_on_update?)
      properties = { key.name => key.to_oas2 }
      writable.each { |p| properties[p.name] = p.to_oas2 }
      { 'properties' => properties, 'required' => [key.name] }
    end

    def get_input_schema(entity_type, tool_name:)
      key = entity_type.property_refs.first
      properties = { key.name => key.to_oas2 }
      select_value = query_option('string', 'Comma-separated properties to return')
      add_alias!(properties, entity_type, '$select', select_value, tool_name: tool_name)
      { 'properties' => properties, 'required' => [key.name] }
    end

    def delete_input_schema(entity_type)
      key = entity_type.property_refs.first
      { 'properties' => { key.name => key.to_oas2 }, 'required' => [key.name] }
    end

    def alias_for(query_option_key)
      QUERY_OPTION_ALIASES.fetch(query_option_key)
    end

    def query_option(type, description = nil)
      { 'type' => type, 'description' => description }.compact
    end
  end
end
