module OdataDuty
  class Filter
    def self.parse(str)
      validate(str)
      separator = or?(str) ? ' or ' : ' and '
      split_outside_quotes(str, separator).map { |s| new(s) }
    end

    def self.or?(str)
      mask_quoted(str).include?(' or ')
    end

    def self.validate(str)
      masked = mask_quoted(str)
      if masked.include?(' and ') && masked.include?(' or ')
        raise NotYetSupportedError, 'mixed AND/OR not supported'
      end

      %w[add sub mul div mod].each do |operator|
        if masked.include?(" #{operator} ")
          raise NotYetSupportedError,
                'filtering with arithmetic operators not supported'
        end
      end
      return unless masked.include?('(')

      raise NotYetSupportedError,
            'filtering does not support functions or Grouping Operators'
    end

    # Replace the contents of single-quoted literals with spaces so substring
    # checks never match separators inside a value. Doubled quotes ('') escape.
    def self.mask_quoted(str)
      in_quote = false
      str.each_char.map do |char|
        if char == "'"
          in_quote = !in_quote
          char
        else
          in_quote ? ' ' : char
        end
      end.join
    end

    def self.split_outside_quotes(str, separator)
      masked = mask_quoted(str)
      segments = []
      start = 0
      while (index = masked.index(separator, start))
        segments << str[start...index]
        start = index + separator.length
      end
      segments << str[start..]
      segments
    end

    private_class_method :mask_quoted, :split_outside_quotes

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
          raise NotYetSupportedError, 'nested property filtering not supported yet'
        end
      end.to_sym
    end
  end
end
