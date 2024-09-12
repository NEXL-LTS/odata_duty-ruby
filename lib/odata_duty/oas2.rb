module OdataDuty
  class OAS2
    def self.build_json(schema)
      builder = new(schema)
      builder.add_error_definition
      builder.add_enum_definitions
      builder.add_complex_definitions
      builder.add_collection_paths
      builder.add_individual_paths
      builder.hash
    end

    attr_reader :hash, :schema

    def initialize(schema)
      @schema = schema
      @hash = { 'swagger' => '2.0', 'info' => {}, 'host' => schema.host,
                'schemes' => [schema.scheme], 'basePath' => schema.base_path,
                'paths' => {}, 'definitions' => {} }
      hash['info']['version'] = schema.version if schema.version
      hash['info']['title'] = schema.title if schema.title
    end

    ERROR_PROPERTIES = {
      'code' => { 'type' => 'string', 'description' => 'A service-defined error code.' },
      'message' => { 'type' => 'string', 'description' => 'A human-readable message.' },
      'target' => { 'type' => 'string', 'description' => 'The target of the error.',
                    'x-nullable' => true }
    }.freeze
    def add_error_definition
      hash['definitions']['Error'] = {
        'type' => 'object',
        'properties' => {
          'error' => {
            'type' => 'object',
            'properties' => ERROR_PROPERTIES
          }
        }
      }
    end

    def add_enum_definitions
      schema.enum_types.each do |enum_type|
        hash['definitions'][enum_type.name] = enum_type.to_oas2
      end
    end

    def add_complex_definitions
      (schema.complex_types + schema.entity_types).each do |complex_type|
        hash['definitions'][complex_type.name] = complex_type.to_oas2
      end
    end

    def add_collection_paths
      schema.collection_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}"] = {
          'get' => entity_set.collection.to_oas2,
          'post' => CollectionPostPath.to_oas2(entity_set)
        }
      end
    end

    def add_individual_paths
      schema.individual_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}({id})"] = {
          'get' => entity_set.individual.to_oas2
        }
      end
    end

    class CollectionPostPath
      def self.to_oas2(entity_set)
        path_info = new(entity_set)
        {
          'operationId' => path_info.operation_id,
          'produces' => path_info.produces,
          'parameters' => path_info.parameters,
          'responses' => path_info.responses
        }
      end

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def operation_id
        "Create#{@entity_set.name}"
      end

      def produces
        ['application/json']
      end

      def parameters
        [
          {
            'name' => 'body', 'in' => 'body', 'required' => true, 'schema' => entity_type_schema
          }
        ]
      end

      def responses
        {
          '200' => { 'description' => 'Success', 'schema' => entity_type_schema },
          '201' => { 'description' => 'Created', 'schema' => entity_type_schema },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      end

      private

      def entity_type_schema
        { '$ref' => "#/definitions/#{@entity_set.entity_type.name}" }
      end
    end
  end
end
