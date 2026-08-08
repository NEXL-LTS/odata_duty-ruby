module OdataDuty
  class EnumMember
    attr_reader :name, :description

    def initialize(name, description: nil)
      @name = name.to_str
      @description = Property.resolve_description(@name, description)
    end
  end

  class EnumType
    def self.description(text = nil)
      @description = Property.resolve_description(__metadata.name, text) if text
      @description
    end

    def self.members
      @members ||= []
    end

    def self.member(name, **)
      members << EnumMember.new(name, **)
    end

    class Metadata
      attr_reader :enum_type

      def initialize(enum_type)
        @enum_type = enum_type
      end

      def members
        enum_type.members
      end

      def description
        enum_type.description
      end

      def scalar?
        true
      end

      def name
        enum_type.to_s.split('::').last.sub(/EnumType\z/, '').sub(/Enum\z/, '')
      end

      def metadata_type
        :enum
      end

      def property_type
        name
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    attr_reader :object

    def initialize(object, _context)
      @object = object
    end

    def self.to_value(*)
      new(*).__to_value
    end

    def __to_value
      return object if __member_names.include?(object)

      raise InvalidValue, "#{object} is not a valid member of #{__member_names}"
    end

    def __member_names
      @__member_names ||= self.class.members.map(&:name)
    end
  end
end
