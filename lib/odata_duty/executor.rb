module OdataDuty
  class Executor # rubocop:disable Metrics/ClassLength
    def self.execute(**kwargs)
      new(**kwargs).execute
    end

    def self.create(**kwargs)
      new(**kwargs).create
    end

    attr_reader :schema, :url, :context, :query_options

    def initialize(schema:, url:, context:, query_options:)
      @schema = schema
      @url = url
      @base_url = schema.base_url.to_str
      @context = context
      @query_options = query_options
    end

    def points = schema.endpoints

    require 'delegate'
    class ContextWrapper < SimpleDelegator
      attr_reader :caller_context, :base_url, :endpoint, :query_options

      def initialize(caller_context, base_url:, endpoint:, query_options: nil)
        super(caller_context)
        @base_url = base_url.chomp('/')
        @endpoint = endpoint
        @query_options = (query_options || {}).to_h
      end

      def od_full_url(path, anchor: nil, **query_params)
        path = [base_url, *path.split('/')].compact.join('/')
        URI.parse(path).tap do |uri|
          uri.query = URI.encode_www_form(query_params) if query_params.any?
          uri.fragment = anchor if anchor
        end.to_str
      end

      def current
        @current ||= {}
      end
    end

    def execute
      set_builder = prepare_builder(endpoint, wrapped_context, query_options)
      props = selected(endpoint.entity_type, query_options['$select']) if query_options['$select']
      apply_select(set_builder, props)

      if url.include?('(')
        individual(set_builder, endpoint, wrapped_context, props)
      elsif url.include?('/$count')
        set_builder.count
      else
        collection(set_builder, endpoint, wrapped_context, query_options, props)
      end
    end

    def create
      Oj.dump(endpoint
          .create(context: wrapped_context)
          .merge(
            '@odata.context': wrapped_context.od_full_url('$metadata',
                                                          anchor: "#{endpoint.name}/$entity")
          ),
              mode: :compat)
    rescue NoMethodError
      raise NoImplementationError, "create not implemented for #{endpoint.url}"
    end

    def prepare_builder(endpoint, context, query_options)
      endpoint.new_entity_set(context: context).tap do |set_builder|
        if query_options.key?('$filter')
          apply_filter(endpoint, set_builder, query_options['$filter'])
        end
      end
    end

    private

    def wrapped_context
      @wrapped_context ||= ContextWrapper.new(context, base_url: schema.base_url,
                                                       endpoint: endpoint,
                                                       query_options: query_options)
    end

    def endpoint
      @endpoint ||= points
                    .find { |e| url.split('/$count').first.split('(').first == e.url }
                    .tap do |result|
        raise UnknownPropertyError, "No endpoint #{url} found in #{urls}" unless result
      end
    end

    def urls = points.map(&:url)

    def apply_filter(endpoint, set_builder, filter_string)
      Filter.parse(filter_string).each do |filter|
        property = endpoint.entity_type.properties.find { |p| p.name == filter.property_name }
        assert_filter_valid_for_property(filter, property)

        value = property.filter_convert(filter.value, set_builder.context)

        _filter(filter, set_builder, value)
      end
    end

    def assert_filter_valid_for_property(filter, property)
      raise UnknownPropertyError, "No such property #{filter.property_name}" unless property

      return unless property.collection? && !filter.collection_operation?

      raise InvalidQueryOptionError,
            "Cannot apply '#{filter.operation}' to a collection property '#{property.name}'."
    end

    def _filter(filter, set_builder, value)
      specific_method = :"od_filter_#{filter.property_name}_#{filter.operation}"
      generic_method = :"od_filter_#{filter.operation}"
      if set_builder.respond_to?(specific_method)
        set_builder.public_send(specific_method, value)
      elsif set_builder.respond_to?(generic_method)
        set_builder.public_send(generic_method, filter.property_name, value)
      else
        raise NoImplementationError, "#{filter.operation} on #{filter.property_name} not supported"
      end
    end

    def extract_value_from_brackets(url)
      match_data = url.match(/.*\(([^)]+)\)/)
      return nil unless match_data

      value = match_data[1]

      value.gsub(/^"|"$/, '').gsub(/^'|'$/, '')
    end

    def selected(entity_type, select_query)
      valid_selected(select_query.split(',').map(&:strip)).map do |p|
        entity_type.properties.find { |a| a.name.to_s == p }.tap do |prop|
          raise UnknownPropertyError, "The property '#{p}' does not exist" unless prop
        end
      end
    rescue UnknownPropertyError, InvalidQueryOptionError => e
      e.backtrace.unshift entity_type._defined_at_ if entity_type.respond_to?(:_defined_at_)
      raise e
    end

    def valid_selected(selected)
      selected.each do |p|
        unless Property.valid_name?(p)
          raise InvalidQueryOptionError, "The property '#{p}' is not valid"
        end
        if p.include?('/')
          raise InvalidQueryOptionError, "The property '#{p}' Cannot be directly selected"
        end
      end
    end

    def apply_remaining(query_options, set_builder)
      query_options.except('$count', '$filter', '$select')
                   .select { |k, _| k.start_with?('$') }.each do |k, v|
        send("apply_#{k[1, 10]}", set_builder, v)
      rescue NoMethodError
        raise NoImplementationError, "query option #{k} not supported"
      end
    end

    def apply_select(set_builder, props)
      return unless set_builder.respond_to?(:od_select)

      selected = (props || endpoint.entity_type.properties).map(&:name)
      selected += endpoint.entity_type.property_refs.map(&:name)
      set_builder.od_select(selected.uniq)
    end

    def apply_top(set_builder, top)
      set_builder.od_top(top) if top
    rescue NoMethodError
      raise NoImplementationError, "top not implemented for #{entity_set}"
    end

    def apply_skip(set_builder, skip)
      set_builder.od_skip(skip) if skip
    rescue NoMethodError
      raise NoImplementationError, "skip not implemented for #{entity_set}"
    end

    def apply_skiptoken(set_builder, top)
      set_builder.od_skiptoken(top) if top
    rescue NoMethodError
      raise NoImplementationError, "skip not implemented for #{entity_set}"
    end

    def add_next_link(data, endpoint, set_builder, query_options, context)
      return unless set_builder.od_next_link_skiptoken

      next_query_options = query_options.merge(:$skiptoken => set_builder.od_next_link_skiptoken)
      data[:'@odata.nextLink'] = context.od_full_url(endpoint.url, **next_query_options)
    end

    require 'oj'

    def collection(set_builder, endpoint, context, query_options, props)
      count = set_builder.count if query_options['$count'] == 'true'
      apply_remaining(query_options, set_builder)
      data = { '@odata.context' => context.od_full_url('$metadata', anchor: endpoint.name),
               'value' => endpoint.collection(set_builder, context: context, selected: props) }
      data['@odata.count'] = count if count
      add_next_link(data, endpoint, set_builder, query_options, context)
      Oj.dump(data, mode: :compat)
    end

    def individual(set_builder, endpoint, context, props)
      entity_id = extract_value_from_brackets(url)

      Oj.dump(
        endpoint
          .individual(set_builder, entity_id, context: context, selected: props)
          .merge(
            '@odata.context': context.od_full_url('$metadata', anchor: "#{endpoint.name}/$entity")
          ),
        mode: :compat
      )
    end
  end
end
