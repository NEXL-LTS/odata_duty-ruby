require_relative 'mapper_builder'

module OdataDuty
  class ComplexType
    def self.description(text = nil)
      @description = Property.resolve_description(__metadata.name, text) if text
      @description
    end

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
        complex_type.to_s.split('::').last.sub(/ComplexType\z/, '').sub(/Complex\z/, '')
      end

      def property_type
        name
      end

      def description
        complex_type.description
      end

      def metadata_type
        :complex
      end

      # callers uniq the result, so duplicates from repeated property types are fine
      def metadata_types(visited = [])
        return [] if visited.include?(complex_type)

        visited << complex_type
        raw_types = properties.map(&:raw_type)
        nested = raw_types.grep(Metadata).flat_map { |m| m.metadata_types(visited) }
        [complex_type] +
          nested +
          raw_types.grep(EnumType::Metadata).map(&:enum_type)
      end

      # nil (falsy) rather than false: callers only consume truthiness
      def scalar?; end
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
