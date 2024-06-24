require_relative 'schema_builder/enum_type'
require_relative 'schema_builder/complex_type'
require_relative 'schema_builder/entity_type'
require_relative 'schema_builder/entity_set'
require_relative 'schema_builder/endpoint'

module OdataDuty
  module SchemaBuilder
    def self.build(**kwargs, &block)
      Schema.new(**kwargs).tap { |s| block.call(s) }
    end

    class Schema
      attr_reader :namespace, :host, :scheme, :base_path, :base_url, :types
      attr_accessor :version, :title

      def initialize(namespace:, host: 'localhost', scheme: 'https', base_path: '')
        @namespace = namespace.to_str.clone.freeze
        @host = host.to_str.clone.freeze
        @scheme = scheme.to_str.clone.freeze
        @base_path = base_path.to_str.clone.freeze
        @base_url = [scheme, '://', host, base_path].join.freeze
        @types = {}
        @containers = {}
      end

      def add_complex_type(**kwargs, &block)
        ComplexType.new(**kwargs).tap do |complex_type|
          add_type complex_type
          block.call(complex_type)
        end
      end

      def add_enum_type(**kwargs, &block)
        EnumType.new(**kwargs).tap do |enum_type|
          add_type enum_type
          block.call(enum_type)
        end
      end

      def add_entity_type(**kwargs, &block)
        EntityType.new(**kwargs).tap do |entity_type|
          add_type entity_type
          block.call(entity_type)
        end
      end

      def add_entity_set(**kwargs)
        EntitySet.new(**kwargs).tap { |entity_set| add_container(entity_set) }
      end

      def endpoints
        entity_sets.map { |entity_set| Endpoint.new(entity_set, 'EntitySet') }
      end

      def enum_types
        all_types.select { |t| t.is_a?(EnumType) }
      end

      def complex_types
        all_types.select { |t| t.is_a?(ComplexType) && !t.is_a?(EntityType) }
      end

      def entity_types
        all_types.select { |t| t.is_a?(EntityType) }
      end

      def entity_sets
        all_containers.select { |t| t.is_a?(EntitySet) }
      end

      def collection_entity_sets
        entity_sets.select { |t| t.resolver_class.instance_methods.include?(:collection) }
      end

      def individual_entity_sets
        entity_sets.select { |t| t.resolver_class.instance_methods.include?(:individual) }
      end

      def execute(url, context:, query_options: {})
        Executor.execute(url: url, context: context, query_options: query_options, schema: self)
      end

      private

      def add_type(type)
        raise "Duplicate #{type.name} type" if @types.key?(type.name)

        @types[type.name] = type
      end

      def all_types = @types.values.sort_by(&:name)

      def add_container(type)
        raise "Duplicate #{type.name} Container" if @containers.key?(type.name)

        @containers[type.name] = type
      end

      def all_containers = @containers.values.sort_by(&:name)
    end
  end
end
