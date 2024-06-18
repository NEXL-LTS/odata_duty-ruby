module OdataDuty
  # rubocop:disable Metrics/MethodLength
  class OAS2
    def self.build_json(schema)
      builder = new(schema)
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

    def add_enum_definitions
      schema.enum_types.each do |enum_type|
        hash['definitions'][enum_type.name] = {
          'type' => 'string',
          'enum' => enum_type.members.map(&:name)
        }
      end
    end

    def add_complex_definitions
      (schema.complex_types + schema.entity_types).each do |complex_type|
        hash['definitions'][complex_type.name] = {
          'type' => 'object',
          'properties' => complex_type.properties.each_with_object({}) do |property, obj|
            obj[property.name.to_s] = property_to_oas2(property)
          end
        }
      end
    end

    def property_to_oas2(property)
      result = if property.raw_type.respond_to?(:to_oas2)
                 if property.collection?
                   { 'type' => 'array', 'items' => property.raw_type.to_oas2 }
                 else
                   property.raw_type.to_oas2
                 end
               elsif property.collection?
                 { 'type' => 'array',
                   'items' => { '$ref' => "#/definitions/#{property.raw_type.name}" } }
               else
                 { '$ref' => "#/definitions/#{property.raw_type.name}" }
               end
      result['x-nullable'] = true if property.nullable
      result
    end

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
        'name' => '$skip_token',
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
      },
      'skip_token' => {
        'type' => 'string',
        'description' => 'Token to be used for $skip_token query option to get the next page of results',
        'x-nullable' => true
      }
    }.freeze

    def add_collection_paths
      schema.collection_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}"] = {
          'get' => {
            'operationId' => "GetCollectionOf#{entity_set.name}",
            'produces' => ['application/json'],
            'parameters' => COLLECTION_PARAMETERS,
            'responses' => {
              'default' => {
                'schema' => {
                  'type' => 'object',
                  'properties' => {
                    'value' => {
                      'type' => 'array',
                      'items' => {
                        '$ref' => "#/definitions/Individual#{entity_set.name}"
                      }
                    }
                  }.merge(COLLECTION_RESPONSE_DEFAULTS)
                }
              }
            }
          }
        }
      end
    end

    def add_individual_paths
      schema.individual_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}({id})"] = {
          'get' => {
            'operationId' => "GetIndividual#{entity_set.name}ById",
            'produces' => ['application/json'],
            'parameters' => [
              {
                'name' => 'id',
                'in' => 'path',
                'required' => true,
                'type' => entity_set.entity_type.integer_property_ref? ? 'integer' : 'string'
              }
            ],
            'responses' => {
              'default' => {
                'schema' => {
                  '$ref' => "#/definitions/Individual#{entity_set.name}"
                }
              }
            }
          }
        }
      end
    end
  end
  # rubocop:enable Metrics/MethodLength
end
