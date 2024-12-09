module OdataDuty
  module SchemaBuilder
    class Endpoint
      attr_reader :entity_set, :kind

      def initialize(entity_set, kind)
        @entity_set = entity_set
        @kind = kind
      end

      def name = entity_set.name
      def url = entity_set.url

      def new_entity_set(**kwargs)
        entity_set.resolver_class.new(**kwargs)
      end

      def entity_type = entity_set.entity_type

      def collection(set_builder, context:)
        begin
          values = set_builder.collection
        rescue NoMethodError
          raise NoImplementationError, "collection not implemented for #{entity_set}"
        end

        mapper = entity_type.mapper(context)

        values.map { |v| mapper.obj_to_hash(v) }
      end

      def individual(id, context:)
        begin
          result = new_entity_set(context: context).individual(converted_id(id, context))
        rescue NoMethodError
          raise NoImplementationError, "individual not implemented for #{entity_set}"
        end

        raise ResourceNotFoundError, "No such entity #{id}" unless result

        mapper = entity_type.mapper(context)

        mapper.obj_to_hash(result)
      end

      def create(context:)
        wrapper = CreateComplexTypeHashWrapper.new(context.query_options, entity_type, context)
        result = new_entity_set(context: context).create(wrapper)
        mapper = entity_type.mapper(context)
        mapper.obj_to_hash(result)
      end

      private

      def converted_id(id, context)
        entity_type.property_refs.first.convert(id, context)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e.message}"
      end
    end
  end
end
