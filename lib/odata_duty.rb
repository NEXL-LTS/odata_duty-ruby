require 'set'

module OdataDuty
  class Error < StandardError; end

  class ServerError < Error; end

  class InvalidValue < ServerError; end

  class ClientError < Error; end

  class ResourceNotFoundError < ClientError; end
  class NoImplementionError < ClientError; end
  class UnknownPropertyError < ClientError; end
  class InvalidFilterValue < ClientError; end
  class InvalidPropertyReferenceValue < ClientError; end

  require 'odata_duty/property'
  require 'odata_duty/enum_type'
  require 'odata_duty/complex_type'
  require 'odata_duty/entity_type'
  require 'odata_duty/filter'

  class EntitySet
    def self.entity_type(entity_type = nil)
      @entity_type = entity_type if entity_type
      @entity_type
    end

    def self.name(name = nil)
      @name = name.to_s if name.is_a?(Symbol)
      @name = name.to_str if name && !name.is_a?(Symbol)
      @name
    end

    def self.url(url = nil)
      @url = url.to_s if url.is_a?(Symbol)
      @url = url.to_str if url && !url.is_a?(Symbol)
      @url
    end

    class Metadata
      attr_reader :entity_set

      def initialize(entity_set)
        @entity_set = entity_set
      end

      def metadata_types
        [entity_set.entity_type].map(&:__metadata).flat_map(&:metadata_types).uniq
      end

      def name
        entity_set.name ||
          entity_set.to_s.split('::').last.gsub(/EntitySet\z/, '').gsub(/Set\z/, '')
      end

      def entity_type
        entity_set.entity_type
      end

      def entity_type_name
        entity_type.__metadata.name
      end

      def kind
        'EntitySet'
      end

      def url
        entity_set.url || name
      end

      def new_entity_set(context:)
        entity_set.new(context: context)
      end

      def collection(set_builder, context:)
        begin
          values = set_builder.collection
        rescue NoMethodError
          raise NoImplementionError, "collection not implemented for #{entity_set}"
        end

        new_values = values.map { |v| entity_type.new(v, context) }
        { value: new_values.map(&:__to_value) }
      end

      def apply_top(set_builder, top)
        set_builder.od_top(top) if top
      rescue NoMethodError
        raise NoImplementionError, "top not implemented for #{entity_set}"
      end

      def apply_skip(set_builder, skip)
        set_builder.od_skip(skip) if skip
      rescue NoMethodError
        raise NoImplementionError, "skip not implemented for #{entity_set}"
      end

      def apply_skiptoken(set_builder, top)
        set_builder.od_skiptoken(top) if top
      rescue NoMethodError
        raise NoImplementionError, "skip not implemented for #{entity_set}"
      end

      def apply_filter(set_builder, filter_string)
        Filter.parse(filter_string).each do |filter|
          property = entity_type.properties.find { |p| p.name == filter.property_name }
          raise UnknownPropertyError, "No such property #{filter.property_name}" unless property

          value = property.filter_convert(filter.value, set_builder.context)

          _filter(filter, set_builder, value)
        end
      end

      def individual(id, context:)
        begin
          result = entity_set.new(context: context).individual(converted_id(id, context))
        rescue NoMethodError
          raise NoImplementionError, "individual not implemented for #{entity_set}"
        end

        raise ResourceNotFoundError, "No such entity #{id}" unless result

        entity_type.new(result, context).__to_value
      end

      private

      def converted_id(id, context)
        entity_type.property_refs.first.convert(id, context)
      rescue OdataDuty::InvalidValue => e
        raise InvalidPropertyReferenceValue, "Invalid individual id : #{e.message}"
      end

      def _filter(filter, set_builder, value)
        specific_method = :"od_filter_#{filter.property_name}_#{filter.operation}"
        generic_method = :"od_filter_#{filter.operation}"
        if set_builder.respond_to?(specific_method)
          set_builder.public_send(specific_method, value)
        elsif set_builder.respond_to?(generic_method)
          set_builder.public_send(generic_method, filter.property_name, value)
        else
          raise NoImplementionError, "#{filter.operation} on #{filter.property_name} not supported"
        end
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    attr_reader :context

    def initialize(context:)
      @context = context
      od_after_init
    end

    def od_after_init; end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end
  end

  class Schema
    def self.namespace(name = nil)
      @namespace = name if name
      @namespace
    end

    def self.entity_sets(entity_sets = nil)
      @entity_sets = entity_sets.uniq if entity_sets
      @entity_sets
    end

    class Metadata
      attr_reader :schema

      def initialize(schema)
        @schema = schema
      end

      def namespace
        schema.namespace
      end

      def entity_sets
        schema.entity_sets.map(&:__metadata)
      end

      def metadata_types
        @metadata_types ||= entity_sets.flat_map(&:metadata_types).uniq.map(&:__metadata)
      end

      def entity_types
        metadata_types.select { |mt| mt.metadata_type == :entity }
      end

      def complex_types
        metadata_types.select { |mt| mt.metadata_type == :complex }
      end

      def enum_types
        metadata_types.select { |mt| mt.metadata_type == :enum }
      end

      def singletons
        []
      end

      def endpoints
        entity_sets + singletons
      end

      def check_names
        names = Set.new
        (enum_types + complex_types + entity_types).each do |et|
          raise "Duplicate #{et.name} type" if names.include?(et.name)

          names << et.name
        end
      end
    end

    def self.__metadata
      Metadata.new(self)
    end

    def self.metadata_xml
      require 'erb'

      metadata = __metadata
      metadata.check_names

      b = binding
      # create and run templates, filling member data variables
      erb = ERB.new(File.read("#{__dir__}/metadata.xml.erb"), trim_mode: '<>')
      erb.location = ["#{__dir__}/metadata.xml.erb", 1]
      erb.result b
    end

    def self.index_hash(metadata_url)
      {
        '@odata.context': metadata_url,
        value: __metadata.endpoints.map do |e|
          { name: e.name, kind: e.kind, url: e.url }
        end
      }
    end

    def self.points
      __metadata.endpoints
    end

    def self.urls
      points.map(&:url)
    end

    def self.extract_value_from_brackets(url)
      match_data = url.match(/.*\(([^)]+)\)/)
      return nil unless match_data

      value = match_data[1]

      value.gsub(/^"|"$/, '').gsub(/^'|'$/, '')
    end

    require 'delegate'
    class ContextWrapper < SimpleDelegator
      attr_accessor :endpoint
    end

    def self.execute(url, context:, query_options: {})
      endpoint = points.find { |e| url.split('/$count').first.split('(').first == e.url }
      raise UnknownPropertyError, "No endpoint #{url} found in #{urls}" unless endpoint

      context = ContextWrapper.new(context)
      context.endpoint = endpoint

      entity_id = extract_value_from_brackets(url)
      return individual(endpoint, entity_id, context) if url.include?('(')

      set_builder = prepare_builder(endpoint, context, query_options)
      return set_builder.count if url.include?('/$count')

      collection(set_builder, endpoint, context, query_options)
    end

    def self.prepare_builder(endpoint, context, query_options)
      endpoint.new_entity_set(context: context).tap do |set_builder|
        if query_options.key?('$filter')
          endpoint.apply_filter(set_builder, query_options['$filter'])
        end
      end
    end

    require 'oj'

    def self.individual(endpoint, entity_id, context)
      Oj.dump(
        endpoint
          .individual(entity_id, context: context)
          .merge(
            '@odata.context': context.url_for(url: '$metadata', anchor: "#{endpoint.name}/$entity")
          ),
        mode: :compat
      )
    end

    def self.collection(set_builder, endpoint, context, query_options)
      count = set_builder.count if query_options['$count'] == 'true'
      apply_remaining(query_options, endpoint, set_builder)
      data = endpoint
             .collection(set_builder, context: context)
             .merge('@odata.context': context.url_for(url: '$metadata', anchor: endpoint.name))
      data['@odata.count'] = count if count
      add_next_link(data, endpoint, set_builder, query_options, context)
      Oj.dump(data, mode: :compat)
    end

    def self.apply_remaining(query_options, endpoint, set_builder)
      query_options.except('$count', '$filter')
                   .select { |k, _| k.start_with?('$') }.each do |k, v|
        endpoint.public_send("apply_#{k[1, 10]}", set_builder, v)
      rescue NoMethodError
        raise NoImplementionError, "query option #{k} not supported"
      end
    end

    def self.add_next_link(data, endpoint, set_builder, query_options, context)
      return unless set_builder.od_next_link_skiptoken

      next_query_options = query_options.merge(url: endpoint.url,
                                               :$skiptoken => set_builder.od_next_link_skiptoken)
      data[:'@odata.nextLink'] = context.url_for(**next_query_options)
    end
  end
end
