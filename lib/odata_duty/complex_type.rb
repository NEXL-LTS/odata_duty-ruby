require_relative 'mapper_builder'

module OdataDuty
  class ComplexType
    def self.properties
      @properties ||= []
    end

    def self.property(name, *args, **kwargs)
      if properties.any? { |p| p.name == name.to_sym }
        raise PropertyAlreadyDefinedError, "#{name} is already defined"
      end

      Property.new(name, *args, **kwargs).tap do |property|
        properties << property
      end
    end

    class Metadata
      attr_reader :complex_type

      def initialize(complex_type)
        @complex_type = complex_type
      end

      def properties
        complex_type.properties
      end

      def name
        complex_type.to_s.split('::').last.gsub(/ComplexType\z/, '').gsub(/Complex\z/, '')
      end

      def property_type
        name
      end

      def metadata_type
        :complex
      end

      def metadata_types
        raw_types = properties.map(&:raw_type)
        complex_meta = raw_types.select { |r| r.is_a?(Metadata) }
                                .select { |m| m.metadata_type == :complex }
        complex_types = complex_meta.flat_map(&:metadata_types)
        ([complex_type] +
           complex_types +
          raw_types.select { |r| r.is_a?(EnumType::Metadata) }.map(&:enum_type)).uniq
      end

      def scalar?
        false
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    attr_reader :object
    attr_reader :od_context

    def initialize(object, context)
      @object = object
      @od_context = context
    end
  end
end
