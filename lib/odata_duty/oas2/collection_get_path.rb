require 'odata_duty/oas2/collection_get_parameters'

module OdataDuty
  class OAS2
    CollectionGetPath = Struct.new(:entity_set, :context) do
      COLLECTION_RESPONSE_DEFAULTS = {
        '@odata.nextLink' => {
          'type' => 'string',
          'description' => 'Url for next page of results',
          'x-nullable' => true
        },
        '@odata.count' => {
          'type' => 'integer',
          'description' => 'Total count of results, if $count set to true',
          'x-nullable' => true
        }
      }.freeze

      def to_oas2
        {
          'operationId' => "GetCollectionOf#{entity_set.name}"
        }.merge(summary_and_description).merge(
          'produces' => ['application/json'],
          'parameters' => CollectionGetParameters.build(entity_set, context),
          'responses' => { '200' => oas2_success_response, 'default' => DEFAULT_ERROR_RESPONSE }
        )
      end

      def summary_and_description
        return {} unless entity_set.description

        { 'summary' => OperationVerbs.list(entity_set.name),
          'description' => entity_set.description }
      end

      def oas2_success_response
        { 'description' => 'Collection Response',
          'schema' => {
            'type' => 'object',
            'properties' => { 'value' => {
              'type' => 'array',
              'items' => { '$ref' => "#/definitions/#{entity_set.entity_type_name}" }
            } }.merge(COLLECTION_RESPONSE_DEFAULTS)
          } }
      end
    end
  end
end
