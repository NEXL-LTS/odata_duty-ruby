require_relative 'complex_type'

module OdataDuty
  module SchemaBuilder
    class EntityType < ComplexType
      attr_reader :property_refs

      def initialize(**kwargs)
        super
        @property_refs = []
      end

      def property_ref(*args, **kwargs)
        kwargs[:mutability] = :computed unless kwargs.key?(:mutability) || kwargs.key?(:computed)
        property(*args, nullable: false, **kwargs).tap do |property|
          raise 'Multiple Property Reference not yet supported' if property_refs.size.positive?

          property_refs << property
        end
      end

      # :nocov: unused accessor; callers read property_refs.first directly
      def prop_ref
        property_refs.first
      end
      # :nocov:

      def mapper(context, selected:)
        context.current['odata_url_base'] ||= context.od_full_url(context.endpoint.url)
        if integer_property_ref?
          int_mapper(context, selected: selected)
        else
          string_mapper(context, selected: selected)
        end
      end

      def int_mapper(context, selected:)
        MapperBuilder.build(self, selected: selected) do |result, obj|
          result['@odata.id'] = "#{context.current['odata_url_base']}(#{obj.id})"
        end
      end

      def string_mapper(context, selected:)
        MapperBuilder.build(self, selected: selected) do |result, obj|
          result['@odata.id'] = "#{context.current['odata_url_base']}('#{obj.id}')"
        end
      end

      def integer_property_ref?
        @property_ref_raw_type ||= property_refs.first.raw_type
        @property_ref_raw_type == EdmInt64
      end
    end
  end
end
