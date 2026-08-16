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

  # Class-DSL definition surface: methods a consumer writes inside a
  # `class < OdataDuty::Schema` / `< OdataDuty::EntitySet` body (and reads back
  # in assertions). These readers double as writers, so the guard cannot flag
  # class-DSL reader misuse of them — an accepted limitation.
  CLASS_DSL_ROWS = {
    OdataDuty::Schema =>
      %i[execute create update delete metadata_xml index_hash to_mcp_server
         namespace version title description entity_sets base_url],
    OdataDuty::EntitySet => %i[entity_type name url description context od_next_link_skiptoken]
  }.freeze

  # Builder-DSL entry points.
  BUILDER_DSL_ROWS = {
    OdataDuty::SchemaBuilder => %i[build],
    OdataDuty::SchemaBuilder::Schema =>
      %i[execute create update delete metadata_xml index_hash to_mcp_server add_entity_type
         add_complex_type add_enum_type add_entity_set version= title= description= inspect],
    OdataDuty::SetResolver => %i[context od_next_link_skiptoken]
  }.freeze

  # Objects the gem hands to consumer resolver/property hooks at request time:
  # the request-context wrapper, the `od_filter_or` predicate value object, and
  # the class-DSL property-method helpers (`object`/`od_context`).
  HOOK_OBJECT_ROWS = {
    OdataDuty::ContextWrapper => %i[base_url od_full_url query_options current],
    OdataDuty::FilterPredicate => %i[property_name operation value],
    OdataDuty::ComplexType => %i[object od_context]
  }.freeze

  # Documented rendering/entry-point surfaces.
  RENDER_ROWS = {
    OdataDuty::EdmxSchema => %i[metadata_xml index_hash],
    OdataDuty::OAS2 => %i[build_json],
    OdataDuty::SearchExpression => %i[terms or? and?],
    OdataDuty::SearchTerm => %i[value not? to_s]
  }.freeze

  METHOD_ROWS = [CLASS_DSL_ROWS, BUILDER_DSL_ROWS, HOOK_OBJECT_ROWS, RENDER_ROWS]
                .reduce(:merge)
                .transform_values { |names| Set.new(names) }

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

  # Per-run memo of `defined_class -> gem owner (or nil)`. The TracePoint fires on
  # every method entry in the whole suite, so resolving the owner (singleton_class?,
  # attached_object, Module#name) on each call dominates the overhead; almost every
  # call repeats a handful of `defined_class` objects, so caching the verdict keeps
  # the hot path an O(1) hash lookup after the first sighting.
  OWNER_CACHE = {}.compare_by_identity

  def self.check(trace)
    owner = gem_owner(trace.defined_class)
    return unless owner

    allowed = ALLOWLIST[owner]
    return if allowed&.include?(trace.method_id)

    raise_if_spec_call_site(owner, trace.method_id)
  end

  def self.gem_owner(defined_class)
    return OWNER_CACHE[defined_class] if OWNER_CACHE.key?(defined_class)

    owner = resolve_owner(defined_class)
    OWNER_CACHE[defined_class] = gem_class?(owner) ? owner : nil
  end

  def self.resolve_owner(defined_class)
    return defined_class.attached_object if defined_class.singleton_class?

    defined_class
  end

  # Resolve the constant name via Module#name directly: gem DSL classes override
  # `self.name` (e.g. OdataDuty::EntitySet.name) with a different arity.
  MODULE_NAME = Module.instance_method(:name)

  def self.gem_class?(owner)
    return false unless owner.is_a?(Module)

    name = MODULE_NAME.bind_call(owner)
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
