# Helper module for testing RuboCop cops
# Not a spec file itself, so doesn't match *_spec.rb pattern
module RubocopCopTestHelper
  ALLOWED_CONSTANTS = [
    'OdataDuty::EntityType',
    'OdataDuty::ComplexType',
    'OdataDuty::EnumType',
    'OdataDuty::EntitySet',
    'OdataDuty::SetResolver',
    'OdataDuty::Schema',
    'OdataDuty::SchemaBuilder',
    'OdataDuty::EdmxSchema',
    'OdataDuty::OAS2',
    'OdataDuty::SearchExpression',
    'OdataDuty::SearchTerm',
    'OdataDuty::Generators::InstallGenerator',
    'OdataDuty::Generators::EntitySetGenerator'
  ].freeze
  ALLOWED_PATTERNS = [
    '\AOdataDuty::\w*Error\z',
    '\AOdataDuty::Invalid\w+\z'
  ].freeze

  def default_cop_config
    {
      'Namespace' => 'OdataDuty',
      'AllowedConstants' => ALLOWED_CONSTANTS,
      'AllowedConstantPatterns' => ALLOWED_PATTERNS
    }
  end

  def inspect_source(code, cop_cfg = nil)
    cop_cfg ||= default_cop_config
    config = RuboCop::Config.new(
      {
        'AllCops' => { 'TargetRubyVersion' => 3.2 },
        'OdataDuty/PublicApiOnly' => cop_cfg
      }
    )
    cop = RuboCop::Cop::OdataDuty::PublicApiOnly.new(config)
    source = RuboCop::AST::ProcessedSource.new(code, 3.2, 'spec/some_spec.rb')

    cop.send(:begin_investigation, source)
    walk_ast(source.ast, cop)

    cop.instance_variable_get(:@current_offenses) || []
  end

  def walk_ast(node, cop)
    return unless node.is_a?(RuboCop::AST::Node)

    dispatch_node(node, cop)
    walk_children(node, cop)
  end

  def dispatch_node(node, cop)
    case node.type
    when :const
      cop.on_const(node)
    when :send
      cop.on_send(node)
    when :csend
      cop.on_csend(node)
    end
  end

  def walk_children(node, cop)
    return unless node.respond_to?(:children)

    node.children.each do |child|
      walk_ast(child, cop) if child.is_a?(RuboCop::AST::Node)
    end
  end
end
