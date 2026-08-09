module OdataDuty
  class OAS2
    class IndividualDeletePath
      def self.to_oas2(entity_set)
        path_info = new(entity_set)
        {
          'operationId' => path_info.operation_id
        }.merge(path_info.summary_and_description).merge(
          'parameters' => path_info.parameters,
          'responses' => path_info.responses
        )
      end

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def operation_id
        "Delete#{@entity_set.name}"
      end

      def summary_and_description
        return {} unless @entity_set.description

        { 'summary' => OperationVerbs.delete(@entity_set.name),
          'description' => @entity_set.description }
      end

      def parameters
        [
          { 'name' => 'id', 'in' => 'path', 'required' => true, 'type' => id_type }
        ]
      end

      def responses
        {
          '204' => { 'description' => 'No Content' },
          'default' => { 'description' => 'Unexpected error',
                         'schema' => { '$ref' => '#/definitions/Error' } }
        }
      end

      private

      def id_type
        @entity_set.entity_type.integer_property_ref? ? 'integer' : 'string'
      end
    end
  end
end
