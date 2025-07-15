require 'parslet'

module OdataDuty
  class SearchExpression
    attr_reader :terms, :operator

    def initialize(terms, operator = :and)
      @terms = Array(terms)
      @operator = operator
    end

    def or?
      @operator == :or
    end

    def and?
      @operator == :and
    end

    def self.parse(search_string)
      return SearchExpression.new([]) if search_string.nil? || search_string.strip.empty?

      parse_tree = build_parse_tree(search_string.strip)
      validate_parse_tree(parse_tree)
      transform(parse_tree)
    end

    def self.build_parse_tree(search_string)
      parser = ParsletSearchExpressionParser.new
      parser.parse(search_string)
    rescue Parslet::ParseFailed => e
      if search_string.include?('(') || search_string.include?(')')
        raise NoImplementationError, 'Parentheses are not supported'
      end
      if search_string.include?(' AND ') && search_string.include?(' OR ')
        raise NoImplementationError, 'Mixed AND/OR operators are not supported'
      end

      raise InvalidQueryOptionError, "Invalid search expression: #{e.message}"
    end

    def self.validate_parse_tree(parse_tree)
      and_sub_tree = parse_tree[:explicit_and_expr] || parse_tree[:implicit_and_expr]
      return unless and_sub_tree

      contains_or = and_sub_tree.any? { |t| t.dig(:term, :word).to_s == 'OR' }
      raise NoImplementationError, 'Mixed AND/OR operators are not supported' if contains_or
    end

    def self.transform(parse_tree)
      transformer = ParsletSearchExpressionTransformer.new
      transformer.apply(parse_tree)
    end
  end

  class SearchTerm
    attr_reader :value, :negated

    def initialize(value, negated: false)
      @value = value
      @negated = negated
    end

    def not?
      @negated
    end

    def to_s
      prefix = @negated ? 'NOT ' : ''
      quoted = @value.include?(' ') ? "\"#{@value}\"" : @value
      "#{prefix}#{quoted}"
    end
  end

  class ParsletSearchExpressionParser < Parslet::Parser
    # Basic elements
    rule(:space) { match('\s').repeat(1) }
    rule(:space?) { space.maybe }

    # Word characters - alphanumeric, dots, commas, hyphens, underscores
    rule(:word_char) { match('[a-zA-Z0-9,.\-_]') }
    rule(:word) { word_char.repeat(1).as(:word) }

    # Quoted phrases
    rule(:quoted_phrase) do
      str('"') >>
        (str('"').absent? >> any).repeat.as(:phrase) >>
        str('"')
    end

    # NOT operator
    rule(:not_operator) { str('NOT') >> space }

    # Basic term (word or quoted phrase)
    rule(:basic_term) { quoted_phrase | word }

    # Term with optional negation
    rule(:term) do
      (not_operator >> basic_term).as(:negated_term) |
        basic_term.as(:term)
    end

    # Operators
    rule(:and_operator) { space >> str('AND') >> space }
    rule(:or_operator) { space >> str('OR') >> space }
    rule(:implicit_and) { space }

    # Simplified expression rules
    rule(:or_expression) { term >> (or_operator >> term).repeat(1) }
    rule(:explicit_and_expression) { term >> (and_operator >> term).repeat(1) }
    rule(:implicit_and_expression) { term >> (implicit_and >> term).repeat(1) }
    rule(:single_term_expression) { term }

    # Main expression - try each pattern
    rule(:expression) do
      or_expression.as(:or_expr) |
        explicit_and_expression.as(:explicit_and_expr) |
        implicit_and_expression.as(:implicit_and_expr) |
        single_term_expression.as(:single_term)
    end

    # Root rule
    rule(:search_expression) { space? >> expression >> space? }

    root(:search_expression)
  end

  class ParsletSearchExpressionTransformer < Parslet::Transform
    rule(word: simple(:word)) { word.to_s }
    rule(phrase: simple(:phrase)) { phrase.to_s }

    rule(term: simple(:term)) do
      SearchTerm.new(term.to_s, negated: false)
    end

    rule(negated_term: simple(:term)) do
      SearchTerm.new(term.to_s, negated: true)
    end

    # Single term expressions
    rule(single_term: simple(:term)) do
      SearchExpression.new([term], :and)
    end

    # OR expressions
    rule(or_expr: sequence(:terms)) do
      # Multiple terms in OR expression
      SearchExpression.new(terms, :or)
    end

    # Explicit AND expressions
    rule(explicit_and_expr: sequence(:terms)) do
      # Multiple terms in explicit AND expression
      SearchExpression.new(terms, :and)
    end

    # Implicit AND expressions
    rule(implicit_and_expr: sequence(:terms)) do
      # Multiple terms in implicit AND expression
      SearchExpression.new(terms, :and)
    end
  end
end
