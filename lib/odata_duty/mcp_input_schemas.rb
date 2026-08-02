module OdataDuty
  module McpInputSchemas
    extend self

    # Property names are used as-is (symbols) for keys/required and the root `type: object` is
    # omitted; the MCP SDK normalizes the keys and supplies the root type default.

    def count_input_schema(supports_search:)
      properties = { '$filter' => { 'type' => 'string' } }
      properties['$search'] = { 'type' => 'string' } if supports_search
      { 'properties' => properties, 'required' => [] }
    end

    def list_input_schema(supports_search:)
      properties = {
        '$filter' => { 'type' => 'string', 'description' => 'OData $filter expression' },
        '$select' => { 'type' => 'string',
                       'description' => 'Comma-separated properties to return' }
      }
      if supports_search
        properties['$search'] = { 'type' => 'string',
                                  'description' => 'Search expression (AND, OR, NOT)' }
      end
      properties['$top'] = { 'type' => 'integer', 'description' => 'Max records to return' }
      properties['$skip'] = { 'type' => 'integer', 'description' => 'Records to skip' }
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
        '$select' => { 'type' => 'string',
                       'description' => 'Comma-separated properties to return' }
      }
      { 'properties' => properties, 'required' => [key.name] }
    end

    def delete_input_schema(entity_type)
      key = entity_type.property_refs.first
      { 'properties' => { key.name => key.to_oas2 }, 'required' => [key.name] }
    end
  end
end
