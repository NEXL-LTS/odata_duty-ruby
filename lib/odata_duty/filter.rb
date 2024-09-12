module OdataDuty
  class Filter
    def self.parse(str)
      validate(str)
      str.split(' and ').map { |s| new(s) }
    end

    def self.validate(str)
      %w[add sub mul div mod].each do |operator|
        if str.include?(" #{operator} ")
          raise NoYetSupportedError,
                'filtering with arithmetic operators not supported'
        end
      end
      return unless str.include?('(')

      raise NoYetSupportedError,
            'filtering does not support functions or Grouping Operators'
    end

    attr_reader :filter_string

    def initialize(filter_string)
      @filter_string = filter_string.to_str.clone.freeze
      @components = @filter_string.split(' ', 3).map(&:freeze)
    end

    def value
      @components.last.delete_prefix("'").delete_suffix("'")
    end

    def operation
      @components[1].to_sym
    end

    def collection_operation?
      false # no support for collection operation yet
    end

    def property_name
      @components.first.tap do |name|
        if name.include?('/')
          raise NoYetSupportedError, 'nested property filtering not supported yet'
        end
      end.to_sym
    end

    def to_s
      filter_string
    end
  end
end
