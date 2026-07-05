require 'delegate'

module OdataDuty
  class ContextWrapper < SimpleDelegator
    attr_reader :caller_context, :base_url, :endpoint, :query_options

    def initialize(caller_context, base_url:, endpoint:, query_options:)
      super(caller_context)
      @base_url = base_url.chomp('/')
      @endpoint = endpoint
      @query_options = query_options.to_h
    end

    def od_full_url(path, anchor: nil, **query_params)
      URI.parse([base_url, path].join('/')).tap do |uri|
        uri.query = URI.encode_www_form(query_params) if query_params.any?
        uri.fragment = anchor
      end.to_str
    end

    def current
      @current ||= {}
    end
  end
end
