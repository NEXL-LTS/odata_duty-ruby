module OdataDuty
  class EnumMember
    attr_reader :name

    def initialize(name)
      @name = name.to_str.clone.freeze
    end
  end

  class EnumType
    def self.members
      @members ||= []
    end

    def self.member(*args, **kwargs)
      EnumMember.new(*args, **kwargs).tap do |m|
        members << m
      end
    end

    class Metadata
      attr_reader :enum_type

      def initialize(enum_type)
        @enum_type = enum_type
      end

      def members
        enum_type.members
      end

      def complex?
        false
      end

      def enum?
        true
      end

      def name
        enum_type.to_s.split('::').last.gsub(/EnumType\z/, '').gsub(/Enum\z/, '')
      end

      def metadata_type
        :enum
      end

      def metadata_types
        []
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

    def self.to_value(*args)
      new(*args).__to_value
    end

    def __to_value
      return object if object.nil? || __member_names.include?(object)

      raise InvalidValue, "#{object} is not a valid member of #{__member_names}"
    end

    def __member_names
      @__member_names ||= self.class.members.map(&:name)
    end
  end
end
