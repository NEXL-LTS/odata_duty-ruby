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
      '$skip' => 'odata_skip'
    }.freeze

    def count_input_schema(supports_search:)
      properties = { alias_for('$filter') => { 'type' => 'string' } }
      properties[alias_for('$search')] = { 'type' => 'string' } if supports_search
      { 'properties' => properties, 'required' => [] }
    end

    def list_input_schema(supports_search:)
      properties = {
        alias_for('$filter') => query_option('string', 'OData $filter expression'),
        alias_for('$select') => query_option('string', 'Comma-separated properties to return')
      }
      if supports_search
        properties[alias_for('$search')] = query_option('string',
                                                        'Search expression (AND, OR, NOT)')
      end
      properties[alias_for('$top')] = query_option('integer', 'Max records to return')
      properties[alias_for('$skip')] = query_option('integer', 'Records to skip')
      { 'properties' => properties, 'required' => [] }
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

    def get_input_schema(entity_type)
      key = entity_type.property_refs.first
      properties = {
        key.name => key.to_oas2,
        alias_for('$select') => query_option('string', 'Comma-separated properties to return')
      }
      { 'properties' => properties, 'required' => [key.name] }
    end

    def delete_input_schema(entity_type)
      key = entity_type.property_refs.first
      { 'properties' => { key.name => key.to_oas2 }, 'required' => [key.name] }
    end

    def alias_for(query_option_key)
      QUERY_OPTION_ALIASES.fetch(query_option_key)
    end

    def query_option(type, description)
      { 'type' => type, 'description' => description }
    end
  end
end
