module OdataDuty
  class OAS2
    # The query-option parameters advertised on a collection GET operation. Each one is emitted
    # only when the entity set can serve it, so the document never offers a query option the
    # service would reject; `$select` is ungated, since the projection happens regardless.
    module CollectionGetParameters
      extend self

      FILTER_NAME = '$filter'.freeze
      SELECT_NAME = '$select'.freeze

      COLLECTION_PARAMETERS = [
        {
          'name' => FILTER_NAME,
          'in' => 'query',
          'type' => 'string',
          'description' => 'Filter the results, supporting `and` and flat `or` combinations'
        },
        {
          'name' => '$search',
          'in' => 'query',
          'type' => 'string',
          'description' => 'Search using structured expressions with AND, OR, NOT operators'
        },
        {
          'name' => SELECT_NAME,
          'in' => 'query',
          'type' => 'array',
          'items' => { 'type' => 'string' },
          'collectionFormat' => 'csv',
          'description' => 'Comma-separated list of properties to return'
        },
        {
          'name' => '$top',
          'in' => 'query',
          'type' => 'integer',
          'minimum' => 0,
          'description' => 'Number of results to return'
        },
        {
          'name' => '$skip',
          'in' => 'query',
          'type' => 'integer',
          'minimum' => 0,
          'description' => 'Number of results to skip'
        },
        {
          'name' => '$count',
          'in' => 'query',
          'type' => 'boolean',
          'description' => 'Include count of the results'
        },
        {
          'name' => '$skiptoken',
          'in' => 'query',
          'type' => 'string',
          'description' => 'Token for next page of results'
        }
      ].freeze

      # Query options gated on the resolver responding to the single hook that serves them.
      # `$filter` is gated too, but on any `od_filter_*` hook rather than one name, so it goes
      # through the entity set's capability predicate instead — see `supported?`.
      PARAMETER_REQUIREMENTS = {
        '$top' => :od_top,
        '$count' => :count,
        '$skip' => :od_skip,
        '$skiptoken' => :od_skiptoken,
        '$search' => :od_search
      }.freeze

      def build(entity_set, context)
        instance = entity_set.resolver_class.new(context: context, init_args: entity_set.init_args)
        parameters(entity_set.entity_type).select do |param|
          supported?(param.fetch('name'), entity_set, instance)
        end
      end

      def supported?(name, entity_set, instance)
        return entity_set.supports_filter? if name == FILTER_NAME
        return true unless PARAMETER_REQUIREMENTS.key?(name)

        instance.respond_to?(PARAMETER_REQUIREMENTS.fetch(name))
      end

      # `$select`'s `enum` names the entity type's own properties, so that parameter cannot be
      # static the way the rest of the list is.
      def parameters(entity_type)
        COLLECTION_PARAMETERS.map do |param|
          next param unless param.fetch('name') == SELECT_NAME

          items = param.fetch('items').merge('enum' => property_names(entity_type))
          param.merge('items' => items)
        end
      end

      def property_names(entity_type)
        entity_type.properties.map { |property| property.name.to_s }
      end
    end
  end
end
