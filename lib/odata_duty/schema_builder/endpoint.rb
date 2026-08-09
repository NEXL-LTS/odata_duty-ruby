module OdataDuty
  module SchemaBuilder
    class Endpoint
      attr_reader :entity_set

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def name = entity_set.name
      def url = entity_set.url
      def description = entity_set.description

      def new_entity_set(context:)
        entity_set.resolver_class.new(context: context, init_args: entity_set.init_args)
      end

      def entity_type = entity_set.entity_type

      def collection(set_builder, context:, selected:)
        unless set_builder.respond_to?(:collection)
          raise NoImplementationError, "collection not implemented for #{set_builder.class}"
        end

        values = set_builder.collection
        mapper = entity_type.mapper(context, selected: selected)

        # builder mapping never reads context; pass nil (accept equivalent mutant)
        values.map { |v| mapper.obj_to_hash(v, nil) }
      rescue StandardError => e
        extend_error(e, set_builder, :collection)
      end

      def individual(set_builder, id, context:, selected:)
        unless set_builder.respond_to?(:individual)
          raise NoImplementationError, "individual not implemented for #{set_builder.class}"
        end

        result = set_builder.individual(converted_id(id))
        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.mapper(context, selected: selected).obj_to_hash(result, nil)
      rescue StandardError => e
        extend_error(e, set_builder, :individual)
      end

      def create(context:)
        wrapper = CreateComplexTypeHashWrapper.new(context.query_options, entity_type,
                                                   operation: :create, context: context)
        result = new_entity_set(context: context).create(wrapper)
        mapper = entity_type.mapper(context, selected: nil)
        mapper.obj_to_hash(result, nil)
      end

      def supports_search?
        entity_set.supports_search?
      end

      def supports_collection?
        entity_set.supports_collection?
      end

      def supports_individual?
        entity_set.supports_individual?
      end

      def supports_count?
        entity_set.supports_count?
      end

      def update(id, context:)
        wrapper = CreateComplexTypeHashWrapper.new(context.query_options, entity_type,
                                                   operation: :update, context: context)
        result = new_entity_set(context: context).update(converted_id(id), wrapper)
        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.mapper(context, selected: nil).obj_to_hash(result, nil)
      end

      def delete(id, context:)
        result = new_entity_set(context: context).delete(converted_id(id))
        raise ResourceNotFoundError, "No such entity #{id}" unless result
      end

      def supports_create?
        entity_set.supports_create?
      end

      def supports_update?
        entity_set.supports_update?
      end

      def supports_delete?
        entity_set.supports_delete?
      end

      private

      def extend_error(err, set_builder, method_name)
        klass = set_builder.class
        err.backtrace.unshift(entity_set._defined_at_)
        if set_builder.respond_to?(:od_after_init)
          err.backtrace.unshift(klass.instance_method(:od_after_init).source_location.join(':'))
        end
        if set_builder.respond_to?(method_name)
          err.backtrace.unshift(klass.instance_method(method_name).source_location.join(':'))
        end
        raise
      end

      def converted_id(id)
        entity_type.property_refs.first.convert(id, nil)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e}"
      end
    end
  end
end
