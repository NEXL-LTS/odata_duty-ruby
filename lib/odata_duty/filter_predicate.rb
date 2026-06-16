module OdataDuty
  class FilterPredicate
    attr_reader :property_name, :operation, :value

    def initialize(property_name:, operation:, value:)
      @property_name = property_name
      @operation = operation
      @value = value
      freeze
    end
  end
end
