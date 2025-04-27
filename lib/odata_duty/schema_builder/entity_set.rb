require 'delegate'
require_relative 'container'

module OdataDuty
  module SchemaBuilder
    class EntitySet < Container
      attr_reader :entity_type, :url, :resolver, :init_args

      def initialize(entity_type:, resolver:, name: nil, url: nil, init_args: :_od_none_)
        @resolver = resolver.to_str.clone.freeze
        name = (name&.to_s || @resolver.split('::').last.sub(/Resolver$/, '')).clone.freeze
        super(name: name)
        @url = (url&.to_s || @name).clone.freeze
        @entity_type = entity_type
        @init_args = init_args
      end

      def entity_type_name = entity_type.name

      def resolver_class = Module.const_get(resolver)
    end
  end
end
