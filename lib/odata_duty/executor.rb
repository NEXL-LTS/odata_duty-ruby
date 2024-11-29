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
      @context = context
      @query_options = query_options
    end

    def points = schema.endpoints

    require 'delegate'
    class ContextWrapper
      attr_reader :url_builder, :endpoint, :query_options

      def initialize(url_builder, endpoint:, query_options: nil)
        @url_builder = url_builder
        @endpoint = endpoint
        @query_options = (query_options || {}).to_h
      end

      def url_for(*args, **kwargs)
        url_builder.url_for(*args, **kwargs)
      end

      def current
        @current ||= {}
      end
    end

    def execute
      entity_id = extract_value_from_brackets(url)
      return individual(endpoint, entity_id, wrapped_context) if url.include?('(')

      set_builder = prepare_builder(endpoint, wrapped_context, query_options)
      return set_builder.count if url.include?('/$count')

      collection(set_builder, endpoint, wrapped_context, query_options)
    end

    def create
      Oj.dump(endpoint
          .create(context: wrapped_context)
          .merge(
            '@odata.context': wrapped_context.url_for(url: '$metadata',
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
      @wrapped_context ||= ContextWrapper.new(context, endpoint: endpoint,
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

    def collection(set_builder, endpoint, context, query_options)
      count = set_builder.count if query_options['$count'] == 'true'
      apply_remaining(query_options, set_builder)
      data = endpoint
             .collection(set_builder, context: context)
             .merge('@odata.context': context.url_for(url: '$metadata', anchor: endpoint.name))
      data['@odata.count'] = count if count
      add_next_link(data, endpoint, set_builder, query_options, context)
      Oj.dump(data, mode: :compat)
    end

    def apply_remaining(query_options, set_builder)
      query_options.except('$count', '$filter')
                   .select { |k, _| k.start_with?('$') }.each do |k, v|
        send("apply_#{k[1, 10]}", set_builder, v)
      rescue NoMethodError
        raise NoImplementationError, "query option #{k} not supported"
      end
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

      next_query_options = query_options.merge(url: endpoint.url,
                                               :$skiptoken => set_builder.od_next_link_skiptoken)
      data[:'@odata.nextLink'] = context.url_for(**next_query_options)
    end

    require 'oj'

    def individual(endpoint, entity_id, context)
      Oj.dump(
        endpoint
          .individual(entity_id, context: context)
          .merge(
            '@odata.context': context.url_for(url: '$metadata', anchor: "#{endpoint.name}/$entity")
          ),
        mode: :compat
      )
    end
  end
end
