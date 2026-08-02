module OdataDuty
  module McpInputSchemas
    module_function

    def search_input_schema
      { 'type' => 'object',
        'properties' => { '$search' => {
          'type' => 'string',
          'description' => 'Search query using expressions with AND, OR, NOT operators'
        } },
        'required' => ['$search'] }
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
      { 'type' => 'object', 'properties' => properties, 'required' => [] }
    end

    def create_input_schema(entity_type)
      writable = entity_type.properties.select(&:settable_on_create?)
      properties = writable.to_h { |p| [p.name.to_s, p.to_oas2] }
      required = writable.reject(&:nullable).map { |p| p.name.to_s }
      { 'type' => 'object', 'properties' => properties, 'required' => required }
    end

    def update_input_schema(entity_type)
      key = entity_type.property_refs.first
      writable = entity_type.properties.select(&:settable_on_update?)
      properties = { key.name.to_s => key.to_oas2 }
      writable.each { |p| properties[p.name.to_s] = p.to_oas2 }
      { 'type' => 'object', 'properties' => properties, 'required' => [key.name.to_s] }
    end

    def get_input_schema(entity_type)
      key = entity_type.property_refs.first
      properties = {
        key.name.to_s => key.to_oas2,
        '$select' => { 'type' => 'string',
                       'description' => 'Comma-separated properties to return' }
      }
      { 'type' => 'object', 'properties' => properties, 'required' => [key.name.to_s] }
    end

    def delete_input_schema(entity_type)
      key = entity_type.property_refs.first
      properties = { key.name.to_s => key.to_oas2 }
      { 'type' => 'object', 'properties' => properties, 'required' => [key.name.to_s] }
    end
  end
end
