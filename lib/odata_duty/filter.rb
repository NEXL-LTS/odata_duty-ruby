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
      remaining = str.dup
      mask_quoted(str).split(separator).map do |masked_segment|
        segment = remaining.slice!(0, masked_segment.length)
        remaining.slice!(0, separator.length)
        segment
      end
    end

    private_class_method :mask_quoted, :split_outside_quotes

    def initialize(filter_string)
      @property_name, @operation, @value = filter_string.split(nil, 3)
    end

    def value
      @value.delete_prefix("'").delete_suffix("'")
    end

    def operation
      @operation.to_sym
    end

    def property_name
      if @property_name.include?('/')
        raise NotYetSupportedError, 'nested property filtering not supported yet'
      end

      @property_name.to_sym
    end
  end
end
