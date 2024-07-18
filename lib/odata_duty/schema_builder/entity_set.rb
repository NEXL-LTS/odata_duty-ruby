require 'delegate'
require_relative 'container'

module OdataDuty
  module SchemaBuilder
    class EntitySet < Container
      attr_reader :entity_type, :url, :resolver

      def initialize(entity_type:, resolver:, name: nil, url: nil)
        @resolver = resolver.to_str.clone.freeze
        name = (name&.to_s || @resolver.split('::').last.sub(/Resolver$/, '')).clone.freeze
        super(name: name)
        @url = (url&.to_s || @name).clone.freeze
        @entity_type = entity_type
      end

      def entity_type_name = entity_type.name

      def resolver_class = Module.const_get(resolver)

      def collection = Collection.new(self)
      def individual = Individual.new(self)

      class Collection < SimpleDelegator
        COLLECTION_PARAMETERS = [
          {
            'name' => '$filter',
            'in' => 'query',
            'type' => 'string',
            'description' => 'Filter the results'
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

        def to_oas2
          {
            'operationId' => "GetCollectionOf#{name}",
            'produces' => ['application/json'],
            'parameters' => COLLECTION_PARAMETERS,
            'responses' => { 'default' => oas2_default_response }
          }
        end

        def oas2_default_response
          { 'schema' => {
            'type' => 'object',
            'properties' => {
              'value' => {
                'type' => 'array',
                'items' => { '$ref' => "#/definitions/#{entity_type_name}" }
              }
            }.merge(COLLECTION_RESPONSE_DEFAULTS)
          } }
        end
      end

      class Individual < SimpleDelegator
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
            'default' => {
              'schema' => {
                '$ref' => "#/definitions/#{entity_type_name}"
              }
            }
          }
        end
      end
    end
  end
end
