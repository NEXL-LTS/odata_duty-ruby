require 'date'

module OdataDuty
  class EdmBase
    def self.to_value(*args)
      new(*args).__to_value
    end

    attr_reader :object

    def initialize(object, _context)
      @object = object
    end

    def metadata_type?
      false
    end
  end

  class EdmInt64 < EdmBase
    def self.property_type
      'Edm.Int64'
    end

    def __to_value
      object && Integer(object)
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmString < EdmBase
    def self.property_type
      'Edm.String'
    end

    def __to_value
      object&.to_str
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmDate < EdmBase
    def self.property_type
      'Edm.Date'
    end

    def __to_value
      object&.to_date
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmDateTimeOffset < EdmBase
    def self.property_type
      'Edm.DateTimeOffset'
    end

    def __to_value
      object&.to_datetime&.iso8601
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmBool < EdmBase
    def self.property_type
      'Edm.Boolean'
    end

    VALID_VALUES = [true, false, nil].freeze

    def __to_value
      return true if object == 'true'
      return false if object == 'false'
      return object if VALID_VALUES.include?(object)

      object.to_boolean
    rescue NoMethodError
      raise InvalidValue, "#{object} not boolean value"
    end
  end

  TYPES_MAPPING = { Integer => EdmInt64,
                    String => EdmString,
                    Date => EdmDate,
                    DateTime => EdmDateTimeOffset,
                    TrueClass => EdmBool }.freeze
end
