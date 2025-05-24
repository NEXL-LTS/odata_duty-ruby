require_relative 'mapper_builder'

module OdataDuty
  class EntityType < ComplexType
    def self.property_refs
      @property_refs ||= []
    end

    def self.property_ref(*args)
      property(*args, nullable: false).tap do |property|
        raise 'Multiple Property Reference not yet supported' if property_refs.size.positive?

        property_refs << property
      end
    end

    class Metadata < ComplexType::Metadata
      attr_reader :entity_type

      def initialize(entity_type)
        @entity_type = entity_type
        super
      end

      def name
        entity_type.to_s.split('::').last.gsub(/EntityType\z/, '').gsub(/Entity\z/, '')
      end

      def metadata_type
        :entity
      end

      def property_refs
        entity_type.property_refs
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    def od_endpoint
      od_context.endpoint
    end

    def self.mapper(context, selected:)
      context.current['odata_url_base'] ||= context.od_full_url(context.endpoint.url)
      if property_refs.first.raw_type == EdmInt64
        int_mapper(context, selected: selected)
      else
        string_mapper(context, selected: selected)
      end
    end

    def self.int_mapper(context, selected:)
      MapperBuilder.build(self, selected: selected) do |result, obj|
        result['@odata.id'] = "#{context.current['odata_url_base']}(#{obj.id})"
      end
    end

    def self.string_mapper(context, selected:)
      MapperBuilder.build(self, selected: selected) do |result, obj|
        result['@odata.id'] = "#{context.current['odata_url_base']}('#{obj.id}')"
      end
    end

    def self._defined_at_
      Object.const_source_location(to_s).join(':')
    end

    private

    def odata_id
      self.class.property_refs.first.raw_type == EdmInt64 ? object.id : "'#{object.id}'"
    end
  end
end
