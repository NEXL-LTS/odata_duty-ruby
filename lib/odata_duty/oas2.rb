require_relative 'context_wrapper'
require_relative 'schema_builder/endpoint'

module OdataDuty
  class OAS2
    def self.build_json(schema, context: nil)
      builder = new(schema, context: context)
      builder.add_error_definition
      builder.add_enum_definitions
      builder.add_complex_definitions
      builder.add_request_body_definitions
      builder.add_collection_paths
      builder.add_individual_paths
      builder.hash
    end

    attr_reader :hash, :schema, :context

    def initialize(schema, context:)
      @schema = schema
      @context = context
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

    def add_request_body_definitions
      schema.collection_entity_sets.each do |entity_set|
        next unless entity_set.supports_create?

        name, definition = CollectionPostPath.request_body_definition(entity_set)
        hash['definitions'][name] = definition
      end
    end

    def add_collection_paths
      schema.collection_entity_sets.each do |entity_set|
        path = { 'get' => CollectionGetPath.new(entity_set, wrap_context(entity_set)).to_oas2 }
        path['post'] = CollectionPostPath.to_oas2(entity_set) if entity_set.supports_create?
        hash['paths']["/#{entity_set.url}"] = path
      end
    end

    def add_individual_paths
      schema.individual_entity_sets.each do |entity_set|
        path = { 'get' => IndividualGetPath.new(entity_set).to_oas2 }
        path['patch'] = IndividualPatchPath.to_oas2(entity_set) if entity_set.supports_update?
        path['delete'] = IndividualDeletePath.to_oas2(entity_set) if entity_set.supports_delete?
        hash['paths']["/#{entity_set.url}({id})"] = path
      end
    end

    DEFAULT_ERROR_RESPONSE = {
      'description' => 'Unexpected error',
      'schema' => {
        '$ref' => '#/definitions/Error'
      }
    }.freeze

    private

    def wrap_context(entity_set)
      ContextWrapper.new(@context, base_url: schema.base_url,
                                   endpoint: SchemaBuilder::Endpoint.new(entity_set),
                                   query_options: {})
    end
  end
end

require 'odata_duty/oas2/collection_get_path'
require 'odata_duty/oas2/collection_post_path'
require 'odata_duty/oas2/individual_get_path'
require 'odata_duty/oas2/individual_patch_path'
require 'odata_duty/oas2/individual_delete_path'
