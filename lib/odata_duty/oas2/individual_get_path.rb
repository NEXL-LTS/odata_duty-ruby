module OdataDuty
  class OAS2
    class IndividualGetPath < SimpleDelegator
      def to_oas2
        {
          'operationId' => "GetIndividual#{name}ById",
          'produces' => ['application/json'],
          'parameters' => oas2_parameters,
          'responses' => oas2_responses
        }
      end

      def oas2_parameters
        [
          {
            'name' => 'id',
            'in' => 'path',
            'required' => true,
            'type' => entity_type.integer_property_ref? ? 'integer' : 'string'
          }
        ]
      end

      def oas2_responses
        {
          '200' => {
            'description' => 'Individual Response',
            'schema' => {
              '$ref' => "#/definitions/#{entity_type_name}"
            }
          },
          'default' => DEFAULT_ERROR_RESPONSE
        }
      end
    end
  end
end
