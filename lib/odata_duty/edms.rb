require 'date'

module OdataDuty
  class EdmBase
    def self.scalar?
      true
    end
  end

  class EdmInt64 < EdmBase
    def self.property_type
      'Edm.Int64'
    end

    OAS_TYPE = { 'type' => 'integer', 'format' => 'int64' }.freeze

    def self.to_oas2(is_collection: false)
      return { 'type' => 'array', 'items' => OAS_TYPE } if is_collection

      OAS_TYPE
    end

    def self.to_value(object, _context)
      object && Integer(object)
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmString < EdmBase
    def self.property_type
      'Edm.String'
    end

    OAS_TYPE = { 'type' => 'string' }.freeze

    def self.to_oas2(is_collection: false)
      return { 'type' => 'array', 'items' => OAS_TYPE } if is_collection

      OAS_TYPE
    end

    def self.to_value(object, _context)
      object&.to_str
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmDate < EdmBase
    def self.property_type
      'Edm.Date'
    end

    OAS_TYPE = { 'type' => 'string', 'format' => 'date' }.freeze

    def self.to_oas2(is_collection: false)
      return { 'type' => 'array', 'items' => OAS_TYPE } if is_collection

      OAS_TYPE
    end

    def self.to_value(object, _context)
      return object if object.nil?
      return object.to_date&.iso8601 if object.respond_to?(:to_date)

      Date.parse(object)&.iso8601
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmDateTimeOffset < EdmBase
    def self.property_type
      'Edm.DateTimeOffset'
    end

    OAS_TYPE = { 'type' => 'string', 'format' => 'date-time' }.freeze

    def self.to_oas2(is_collection: false)
      return { 'type' => 'array', 'items' => OAS_TYPE } if is_collection

      OAS_TYPE
    end

    def self.to_value(object, _context)
      return object if object.nil?
      return object.to_datetime&.iso8601 if object.respond_to?(:to_datetime)

      DateTime.parse(object)&.iso8601
    rescue StandardError => e
      raise InvalidValue, e.message
    end
  end

  class EdmBool < EdmBase
    def self.property_type
      'Edm.Boolean'
    end

    OAS_TYPE = { 'type' => 'boolean' }.freeze

    def self.to_oas2(is_collection: false)
      return { 'type' => 'array', 'items' => OAS_TYPE } if is_collection

      OAS_TYPE
    end

    VALID_VALUES = [true, false, nil].freeze

    def self.to_value(object, _context)
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
