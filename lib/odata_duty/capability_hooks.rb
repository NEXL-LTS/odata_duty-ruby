module OdataDuty
  module CapabilityHooks
    FILTER_HOOK_PREFIX = 'od_filter_'.freeze

    def self.filterable?(klass)
      klass.public_instance_methods.any? { |name| name.start_with?(FILTER_HOOK_PREFIX) }
    end
  end
end
