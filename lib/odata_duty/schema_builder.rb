module OdataDuty
  class SchemaBuilder
    def self.build(**kwargs, &block)
      new(**kwargs).tap { |s| block.call(s) }
    end

    attr_reader :namespace, :base_url, :all_types

    def initialize(namespace:, base_url:)
      @namespace = namespace.to_str.clone.freeze
      @base_url = base_url.to_str.clone.freeze
      @types = {}
    end

    class ComplexType
      attr_reader :name, :properties

      def initialize(name:)
        @name = name.to_str.clone.freeze
        @properties = []
      end

      def property(*args, **kwargs)
        Property.new(*args, **kwargs).tap do |property|
          properties << property
        end
      end

      def to_value(val, context)
        properties.each_with_object({}) do |property, obj|
          obj[property.name] = property.to_value(val.public_send(property.name.to_sym), context)
        end
      end
    end

    def add_complex_type(**kwargs, &block)
      ComplexType.new(**kwargs).tap do |complex_type|
        add_type complex_type
        block.call(complex_type)
      end
    end

    class EnumType
      attr_reader :name, :members

      def initialize(name:)
        @name = name.to_str.clone.freeze
        @members = []
      end

      def member(*args)
        @members << EnumMember.new(*args)
      end

      def to_value(val, _context)
        return val if val.nil? || members.map(&:name).include?(val)

        raise InvalidValue, "#{val} is not a valid member of #{members}"
      end
    end

    def add_enum_type(**kwargs, &block)
      EnumType.new(**kwargs).tap do |enum_type|
        add_type enum_type
        block.call(enum_type)
      end
    end

    class EntityType < ComplexType
      attr_reader :property_refs

      def initialize(**kwargs)
        super
        @property_refs = []
      end

      def property_ref(*args)
        property(*args, nullable: false).tap do |property|
          raise 'Multiple Property Reference not yet suported' if property_refs.size.positive?

          property_refs << property
        end
      end

      def to_value(val, context)
        odata_id = property_refs.first.raw_type == EdmInt64 ? val.id : "'#{val.id}'"
        super.merge(
          '@odata.id': context.url_for(url: "#{context.endpoint.url}(#{odata_id})")
        )
      end
    end

    def add_entity_type(**kwargs, &block)
      EntityType.new(**kwargs).tap do |entity_type|
        add_type entity_type
        block.call(entity_type)
      end
    end

    class EntitySet
      attr_reader :name, :entity_type, :url, :resolver

      def initialize(entity_type:, resolver:, name: nil, url: nil)
        @resolver = resolver.to_str.clone.freeze
        @name = (name&.to_s || @resolver.split('::').last.sub(/Resolver$/, '')).clone.freeze
        @url = (url&.to_s || @name).clone.freeze
        @entity_type = entity_type
      end

      def entity_type_name = entity_type.name
    end

    def add_entity_set(**kwargs)
      EntitySet.new(**kwargs).tap do |entity_set|
        add_type entity_set
      end
    end

    Endpoint = Struct.new(:entity_set, :kind) do
      def name = entity_set.name
      def url = entity_set.url

      def new_entity_set(**kwargs)
        Module.const_get(entity_set.resolver).new(**kwargs)
      end

      def entity_type = entity_set.entity_type

      def collection(set_builder, context:)
        begin
          values = set_builder.collection
        rescue NoMethodError
          raise NoImplementionError, "collection not implemented for #{entity_set}"
        end

        new_values = values.map { |v| entity_type.to_value(v, context) }
        { value: new_values }
      end

      def individual(id, context:)
        begin
          result = new_entity_set(context: context).individual(converted_id(id, context))
        rescue NoMethodError
          raise NoImplementionError, "individual not implemented for #{entity_set}"
        end

        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.to_value(result, context)
      end

      private

      def converted_id(id, context)
        entity_type.property_refs.first.convert(id, context)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e.message}"
      end
    end

    def endpoints
      entity_sets.map do |entity_set|
        Endpoint.new(entity_set, 'EntitySet')
      end
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
      all_types.select { |t| t.is_a?(EntitySet) }
    end

    require 'delegate'
    class ContextWrapper < SimpleDelegator
      attr_accessor :endpoint
    end

    def execute(url, context:, query_options: {})
      Executor.execute(url: url, context: context, query_options: query_options, schema: self)
    end

    private

    def add_type(type)
      raise "Duplicate #{type.name} type" if @types.key?(type.name)

      @types[type.name] = type
      @all_types = @types.values.sort_by(&:name)
    end
  end
end
