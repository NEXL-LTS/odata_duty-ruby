require 'odata_duty'

module OdataDuty
  class NonPublicApiError < StandardError; end
end

# Rows below are the method-level public contract of the gem, asserted at runtime
# against every spec call site. Widen a row only as a reviewed public-API change.
module PublicApiGuard
  ERROR_METHODS = %i[message code status target backtrace].freeze

  def self.error_classes
    OdataDuty.constants
             .map { |name| OdataDuty.const_get(name) }
             .select { |const| const.is_a?(Class) && const < StandardError }
  end

  def self.error_allowlist
    error_classes.to_h { |klass| [klass, Set.new(ERROR_METHODS)] }
  end

  METHOD_ROWS = {
    OdataDuty::Schema =>
      %i[execute create update delete metadata_xml index_hash to_mcp_server],
    OdataDuty::SchemaBuilder => %i[build],
    OdataDuty::SchemaBuilder::Schema =>
      %i[execute create update delete metadata_xml index_hash to_mcp_server add_entity_type
         add_complex_type add_enum_type add_entity_set version= title= description= inspect],
    OdataDuty::EdmxSchema => %i[metadata_xml index_hash],
    OdataDuty::OAS2 => %i[build_json],
    OdataDuty::SearchExpression => %i[terms or? and?],
    OdataDuty::SearchTerm => %i[value not? to_s]
  }.transform_values { |names| Set.new(names) }

  ALLOWLIST = METHOD_ROWS.merge(error_allowlist)
                         .each_value(&:freeze)
                         .freeze

  def self.install
    tracepoint = TracePoint.new(:call, :c_call) { |trace| check(trace) }
    tracepoint.enable
    tracepoint
  end

  def self.uninstall(tracepoint)
    tracepoint.disable
  end

  def self.check(trace)
    owner = resolve_owner(trace.defined_class)
    return unless gem_class?(owner)

    allowed = ALLOWLIST[owner]
    return if allowed&.include?(trace.method_id)

    raise_if_spec_call_site(owner, trace.method_id)
  end

  def self.resolve_owner(defined_class)
    return defined_class.attached_object if defined_class.singleton_class?

    defined_class
  end

  def self.gem_class?(owner)
    return false unless owner.is_a?(Module)

    name = owner.name
    !name.nil? && name.start_with?('OdataDuty')
  end

  def self.raise_if_spec_call_site(owner, method_id)
    origin = caller_locations.find { |loc| !loc.path.end_with?('public_api_guard.rb') }
    return unless origin&.path&.end_with?('_spec.rb')

    raise OdataDuty::NonPublicApiError,
          "`#{method_id}` is not part of the public API of #{owner}. " \
          'Assert on rendered output (metadata_xml/build_json/execute) instead.'
  end
end
