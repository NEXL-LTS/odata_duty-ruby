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
