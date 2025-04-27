module OdataDuty
  class SetResolver
    attr_reader :context

    def initialize(context:, init_args:)
      @context = context
      return unless respond_to?(:od_after_init)

      call_od_after_init(init_args)
    end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end

    private

    def call_od_after_init(init_args)
      if init_args == :_od_none_
        od_after_init
      elsif od_init_args_type == :keyword
        od_after_init(**init_args)
      else
        od_after_init(*Array(init_args))
      end
    rescue ArgumentError => e
      raise e unless e.backtrace[0].include?(':in `od_after_init')

      err = InitArgsMismatchError.new(e.message)
      err.set_backtrace(e.backtrace.clone)
      err.backtrace.insert(1, entity_set._defined_at_) if entity_set.respond_to?(:_defined_at_)

      raise err
    end

    def od_init_args_type
      @od_init_args_type ||=
        if od_after_init_parameters.any? { |type| %i[key keyreq keyrest].include?(type) }
          :keyword
        elsif od_after_init_parameters.any? { |type| %i[req opt rest].include?(type) }
          :positional
        else
          :none
        end
    end

    def od_after_init_parameters
      @od_after_init_parameters ||= method(:od_after_init).parameters.map(&:first)
    end

    def entity_set
      context.endpoint.entity_set
    end
  end
end
