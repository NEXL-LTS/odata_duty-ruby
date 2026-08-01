require 'delegate'
require_relative 'container'

module OdataDuty
  module SchemaBuilder
    class EntitySet < Container
      attr_reader :entity_type, :url, :resolver, :init_args

      def initialize(entity_type:, resolver:, name: nil, url: nil, init_args: nil)
        @resolver = resolver.clone
        name = name&.to_s || @resolver.split('::').last.sub(/Resolver\z/, '')
        super(name: name)
        @url = (url&.to_s || @name).clone
        @entity_type = entity_type
        @init_args = init_args
      end

      def entity_type_name = entity_type.name

      def resolver_class = Module.const_get(resolver)

      def supports_search?
        # Check if the resolver class supports search by looking for the od_search method
        resolver_class.method_defined?(:od_search)
      end

      def supports_filter_or?
        resolver_class.method_defined?(:od_filter_or)
      end

      def supports_collection?
        # Check if the resolver class supports read by looking for the collection method
        resolver_class.method_defined?(:collection)
      end

      def supports_create?
        # Check if the resolver class supports create by looking for the create method
        resolver_class.method_defined?(:create)
      end

      def supports_update?
        # Check if the resolver class supports update by looking for the update method
        resolver_class.method_defined?(:update)
      end

      def supports_delete?
        # Check if the resolver class supports delete by looking for the delete method
        resolver_class.method_defined?(:delete)
      end

      def non_insertable_property_names
        @non_insertable_property_names ||=
          entity_type.properties.select(&:non_insertable?).map(&:name)
      end
    end
  end
end
