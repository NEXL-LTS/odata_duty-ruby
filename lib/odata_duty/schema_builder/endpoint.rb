module OdataDuty
  module SchemaBuilder
    class Endpoint
      attr_reader :entity_set

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def name = entity_set.name
      def url = entity_set.url

      def new_entity_set(context:)
        entity_set.resolver_class.new(context: context, init_args: entity_set.init_args)
      end

      def entity_type = entity_set.entity_type

      def collection(set_builder, context:, selected:)
        unless set_builder.respond_to?(:collection)
          raise NoImplementationError, "collection not implemented for #{entity_set}"
        end

        values = set_builder.collection
        mapper = entity_type.mapper(context, selected: selected)

        values.map { |v| mapper.obj_to_hash(v, context) }
      rescue StandardError => e
        extend_error(e, :collection)
      end

      def individual(set_builder, id, context:, selected:)
        unless set_builder.respond_to?(:individual)
          raise NoImplementationError, "individual not implemented for #{entity_set}"
        end

        result = set_builder.individual(converted_id(id, context))
        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.mapper(context, selected: selected).obj_to_hash(result, context)
      rescue StandardError => e
        extend_error(e, :collection)
      end

      def create(context:)
        wrapper = CreateComplexTypeHashWrapper.new(context.query_options, entity_type, context)
        result = new_entity_set(context: context).create(wrapper)
        mapper = entity_type.mapper(context, selected: nil)
        mapper.obj_to_hash(result, context)
      end

      private

      def extend_error(err, method_name)
        err.backtrace.unshift(entity_set._defined_at_) if entity_set.respond_to?(:_defined_at_)
        if set_builder.respond_to?(:od_after_init)
          err.backtrace.unshift(set_builder.method(:od_after_init).source_location.join(':'))
        end
        if set_builder.respond_to?(method_name)
          err.backtrace.unshift(set_builder.method(method_name).source_location.join(':'))
        end
        raise err
      end

      def converted_id(id, context)
        entity_type.property_refs.first.convert(id, context)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e.message}"
      end
    end
  end
end
