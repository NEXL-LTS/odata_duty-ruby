require 'set'

require 'odata_duty/errors'
require 'odata_duty/set_resolver'
require 'odata_duty/schema_builder'
require 'odata_duty/edmx_schema'
require 'odata_duty/executor'
require 'odata_duty/oas2'
require 'odata_duty/property'
require 'odata_duty/enum_type'
require 'odata_duty/complex_type'
require 'odata_duty/entity_type'
require 'odata_duty/filter'
require 'odata_duty/create_complex_type_hash_wrapper'

module OdataDuty
  class EntitySet
    def self.entity_type(entity_type = nil)
      @entity_type = entity_type if entity_type
      @entity_type
    end

    def self.name(name = nil)
      @name = name.to_s if name.is_a?(Symbol)
      @name = name.to_str if name && !name.is_a?(Symbol)
      @name
    end

    def self.url(url = nil)
      @url = url.to_s if url.is_a?(Symbol)
      @url = url.to_str if url && !url.is_a?(Symbol)
      @url
    end

    class Metadata
      attr_reader :entity_set

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def metadata_types
        [entity_set.entity_type].map(&:__metadata).flat_map(&:metadata_types).uniq
      end

      def name
        entity_set.name ||
          entity_set.to_s.split('::').last.gsub(/EntitySet\z/, '').gsub(/Set\z/, '')
      end

      def entity_type
        entity_set.entity_type
      end

      def entity_type_name
        entity_type.__metadata.name
      end

      def kind
        'EntitySet'
      end

      def url
        entity_set.url || name
      end

      def new_entity_set(context:)
        entity_set.new(context: context)
      end

      def collection(set_builder, context:)
        begin
          values = set_builder.collection
        rescue NoMethodError
          raise NoImplementionError, "collection not implemented for #{entity_set}"
        end

        new_values = values.map { |v| entity_type.new(v, context) }
        { value: new_values.map(&:__to_value) }
      end

      def individual(id, context:)
        begin
          result = entity_set.new(context: context).individual(converted_id(id, context))
        rescue NoMethodError
          raise NoImplementionError, "individual not implemented for #{entity_set}"
        end

        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.new(result, context).__to_value
      end

      def create(context:)
        wrapper = CreateComplexTypeHashWrapper.new(context.query_options, entity_type, context)
        result = entity_set.new(context: context)
                           .create(wrapper)
        entity_type.new(result, context).__to_value
      end

      private

      def converted_id(id, context)
        entity_type.property_refs.first.convert(id, context)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e.message}"
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    attr_reader :context

    def initialize(context:)
      @context = context
      od_after_init
    end

    def od_after_init; end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end
  end

  class Schema
    def self.namespace(name = nil)
      @namespace = name if name
      @namespace
    end

    def self.version(name = nil)
      @version = name if name
      @version
    end

    def self.title(name = nil)
      @title = name if name
      @title
    end

    def self.entity_sets(entity_sets = nil)
      @entity_sets = entity_sets.uniq if entity_sets
      @entity_sets
    end

    class Metadata
      attr_reader :schema

      def initialize(schema)
        @schema = schema
      end

      def version = schema.version
      def title = schema.title

      def namespace
        schema.namespace
      end

      def entity_sets
        schema.entity_sets.map(&:__metadata)
      end

      def metadata_types
        @metadata_types ||= entity_sets.flat_map(&:metadata_types).uniq.map(&:__metadata)
      end

      def entity_types
        metadata_types.select { |mt| mt.metadata_type == :entity }
      end

      def complex_types
        metadata_types.select { |mt| mt.metadata_type == :complex }
      end

      def enum_types
        metadata_types.select { |mt| mt.metadata_type == :enum }
      end

      def singletons
        []
      end

      def endpoints
        entity_sets + singletons
      end

      def check_names
        names = Set.new
        (enum_types + complex_types + entity_types).each do |et|
          raise "Duplicate #{et.name} type" if names.include?(et.name)

          names << et.name
        end
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    def self.metadata_xml
      require 'erb'

      metadata = __metadata
      metadata.check_names

      b = binding
      # create and run templates, filling member data variables
      erb = ERB.new(File.read("#{__dir__}/metadata.xml.erb"), trim_mode: '<>')
      erb.location = ["#{__dir__}/metadata.xml.erb", 1]
      erb.result b
    end

    def self.index_hash(metadata_url)
      {
        '@odata.context': metadata_url,
        value: __metadata.endpoints.map do |e|
          { name: e.name, kind: e.kind, url: e.url }
        end
      }
    end

    def self.endpoints
      __metadata.endpoints
    end

    def self.urls
      points.map(&:url)
    end

    def self.execute(url, context:, query_options: {})
      Executor.execute(url: url, context: context, query_options: query_options, schema: self)
    end

    def self.create(url, context:, query_options: {})
      Executor.create(url: url, context: context, query_options: query_options, schema: self)
    end
  end
end
