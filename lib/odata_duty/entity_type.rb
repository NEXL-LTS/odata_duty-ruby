require_relative 'mapper_builder'

module OdataDuty
  class EntityType < ComplexType
    def self.property_refs
      @property_refs ||= []
    end

    def self.property_ref(*args)
      property(*args, nullable: false).tap do |property|
        raise 'Multiple Property Reference not yet suported' if property_refs.size.positive?

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

    def self.mapper(val, context)
      context.current['odata_url_base'] ||= context.url_for(url: context.endpoint.url)
      if property_refs.first.raw_type == EdmInt64
        int_mapper(val, context)
      else
        string_mapper(val, context)
      end
    end

    def self.int_mapper(val, context)
      MapperBuilder.build(self, val) do |result, obj|
        result['@odata.id'] = "#{context.current['odata_url_base']}(#{obj.id})"
      end
    end

    def self.string_mapper(val, context)
      MapperBuilder.build(self, val) do |result, obj|
        result['@odata.id'] = "#{context.current['odata_url_base']}('#{obj.id}')"
      end
    end

    # def __to_value
    #   super.merge(
    #     '@odata.id': od_context.url_for(url: "#{od_endpoint.url}(#{odata_id})")
    #   )
    # end

    private

    def odata_id
      self.class.property_refs.first.raw_type == EdmInt64 ? object.id : "'#{object.id}'"
    end
  end
end
