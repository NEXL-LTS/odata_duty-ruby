module OdataDuty
  class OAS2
    class IndividualPatchPath
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
        "Update#{@entity_set.name}"
      end

      def produces
        ['application/json']
      end

      def parameters
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => id_type },
          { 'name' => 'body', 'in' => 'body', 'required' => true, 'schema' => entity_type_schema }
        ]
      end

      def responses
        {
          '200' => { 'description' => 'Success', 'schema' => entity_type_schema },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      end

      private

      def id_type
        @entity_set.entity_type.integer_property_ref? ? 'integer' : 'string'
      end

      def entity_type_schema
        { '$ref' => "#/definitions/#{@entity_set.entity_type.name}" }
      end
    end
  end
end
