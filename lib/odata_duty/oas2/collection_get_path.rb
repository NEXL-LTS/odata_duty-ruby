module OdataDuty
  class OAS2
    CollectionGetPath = Struct.new(:entity_set) do
      COLLECTION_PARAMETERS = [
        {
          'name' => '$filter',
          'in' => 'query',
          'type' => 'string',
          'description' => 'Filter the results'
        },
        {
          'name' => '$select',
          'in' => 'query',
          'type' => 'array',
          'items' => { 'type' => 'string' },
          'collectionFormat' => 'csv',
          'description' => 'Comma-separated list of properties to return'
        },
        {
          'name' => '$top',
          'in' => 'query',
          'type' => 'integer',
          'description' => 'Number of results to return'
        },
        {
          'name' => '$skip',
          'in' => 'query',
          'type' => 'integer',
          'description' => 'Number of results to skip'
        },
        {
          'name' => '$count',
          'in' => 'query',
          'type' => 'boolean',
          'description' => 'Include count of the results'
        },
        {
          'name' => '$skiptoken',
          'in' => 'query',
          'type' => 'string',
          'description' => 'Token for next page of results'
        }
      ].freeze

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

      PARAMETER_REQUIREMENTS = {
        '$top' => :od_top,
        '$count' => :count,
        '$skip' => :od_skip,
        '$skiptoken' => :od_skiptoken
      }.freeze

      def to_oas2
        instance = entity_set.resolver_class.new(context: nil)
        parameters = COLLECTION_PARAMETERS.select do |param|
          !PARAMETER_REQUIREMENTS.key?(param['name']) ||
            instance.respond_to?(PARAMETER_REQUIREMENTS[param['name']])
        end
        {
          'operationId' => "GetCollectionOf#{entity_set.name}",
          'produces' => ['application/json'],
          'parameters' => parameters,
          'responses' => { '200' => oas2_success_response, 'default' => DEFAULT_ERROR_RESPONSE }
        }
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
