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
          'get' => CollectionGetPath.new(entity_set).to_oas2,
          'post' => CollectionPostPath.to_oas2(entity_set)
        }
      end
    end

    def add_individual_paths
      schema.individual_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}({id})"] = {
          'get' => IndividualGetPath.new(entity_set).to_oas2
        }
      end
    end

    DEFAULT_ERROR_RESPONSE = {
      'description' => 'Unexpected error',
      'schema' => {
        '$ref' => '#/definitions/Error'
      }
    }.freeze
  end
end

require 'odata_duty/oas2/collection_get_path'
require 'odata_duty/oas2/collection_post_path'
require 'odata_duty/oas2/individual_get_path'
