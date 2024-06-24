module OdataDuty
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
          'get' => entity_set.collection.to_oas2
        }
      end
    end

    def add_individual_paths
      schema.individual_entity_sets.each do |entity_set|
        hash['paths']["/#{entity_set.url}({id})"] = {
          'get' => entity_set.individual.to_oas2
        }
      end
    end
  end
end
