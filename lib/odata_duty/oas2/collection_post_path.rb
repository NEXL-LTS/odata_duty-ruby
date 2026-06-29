module OdataDuty
  class OAS2
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

      def self.request_body_definition(entity_set)
        writable = entity_set.entity_type.properties.select(&:settable_on_create?)
        definition = { 'type' => 'object',
                       'properties' => writable.to_h { |p| [p.name.to_s, p.to_oas2] } }
        required = writable.reject(&:nullable).map { |p| p.name.to_s }
        definition['required'] = required unless required.empty?
        ["#{entity_set.entity_type.name}Create", definition]
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
            'name' => 'body', 'in' => 'body', 'required' => true, 'schema' => create_schema
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

      def create_schema
        { '$ref' => "#/definitions/#{@entity_set.entity_type.name}Create" }
      end
    end
  end
end
