unless ENV['MUTANT']
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :branch

    add_filter '/spec/'
    add_filter '/benchmarks/'
    add_filter '/bin/'
    add_filter 'lib/odata_duty/railtie.rb'

    minimum_coverage(line: 100, branch: 100) if ENV['COVERAGE_ENFORCE']
  end
end

require 'byebug'
require 'nokogiri'
require 'odata_duty'
require 'camel_snake_struct'

require_relative 'support/public_api_guard'
# Global, single-install runtime guard: raises NonPublicApiError when a spec calls
# a gem method that is not on the public-API allowlist. Active for both spec-file
# loading and example execution for the whole run (no per-file/per-example opt-in).
PublicApiGuard.install

# The exact `odata_*` query-option argument descriptions the MCP tool input schemas are
# expected to generate. Held here so the list/count/get tool specs on both DSLs assert the
# same literal text rather than four hand-copied copies of it.
module ExpectedMcpDescriptions
  FILTER = 'OData $filter expression; see the service instructions for the grammar. ' \
           'Filtering is supported for this entity set, but not every property or operator ' \
           'combination is necessarily implemented — an unsupported combination returns an ' \
           'error rather than an empty result. Property names are listed under odata_select. ' \
           "Example: user_name eq 'Alice'".freeze
  SEARCH = 'Free-text $search expression; terms combined with AND, OR, NOT. ' \
           'Parenthesised groups are not supported.'.freeze
  SELECT = 'Properties to return; omit for all.'.freeze
  TOP = 'Maximum number of records to return.'.freeze
  SKIP = 'Number of records to skip before returning results.'.freeze
  SKIPTOKEN = 'Continuation token for the next page. Take it from the $skiptoken query ' \
              "parameter of a prior response's @odata.nextLink.".freeze
end

# The exact server `instructions` text `to_mcp_server` is expected to generate for the query-option
# dialect, held here so both DSLs' instructions specs assert the same literal rather than two
# hand-copied copies of it.
module ExpectedMcpInstructions
  INTRO = 'This service exposes a subset of OData v4. Query options are passed to tools as ' \
          '`odata_*` arguments (e.g. `odata_filter` is OData `$filter`).'.freeze
  FILTER_LINE = '$filter: predicates of the form `<property> <op> <value>`. Operators: eq, ne, ' \
                'gt, ge, lt, le. Combine with all `and` or all `or` — mixing `and` with `or` ' \
                'is not supported, nor is parenthesised grouping. Functions (contains, ' \
                'startswith, tolower, …), arithmetic and `not` are not supported. String ' \
                'literals use single quotes; Edm.Date and Edm.DateTimeOffset values are ISO ' \
                '8601 (2024-01-31, 2024-01-31T00:00:00+00:00).'.freeze
  SEARCH_LINE = '$search: terms combined with AND, OR, NOT. Parenthesised groups are not ' \
                'supported.'.freeze
  PAGING_LINE = 'Paging: pass odata_skiptoken with the $skiptoken value from a prior ' \
                "response's @odata.nextLink.".freeze
  UNSUPPORTED_LINE = '$orderby, $expand, $apply, $compute and $count=true are not ' \
                     'supported.'.freeze
  CLOSING = 'Each tool advertises only the query options its entity set supports.'.freeze

  ALL_OPTIONS = "#{INTRO}\n\n#{FILTER_LINE}\n#{SEARCH_LINE}\n#{PAGING_LINE}\n" \
                "#{UNSUPPORTED_LINE}\n\n#{CLOSING}".freeze
  NO_OPTIONS = "#{INTRO}\n\n#{UNSUPPORTED_LINE}\n\n#{CLOSING}".freeze
end

class String
  def to_date
    Date.parse(self)
  end

  def to_datetime
    DateTime.parse(self)
  end
end

module TestHelpers
  def format_xml(xml_string)
    doc = Nokogiri::XML(xml_string) { |config| config.default_xml.noblanks }
    doc.to_xml(indent: 2)
  end

  def entity_sets_from_doc(parsed_xml)
    namespaces = {
      'edmx' => 'http://docs.oasis-open.org/odata/ns/edmx',
      'edm' => 'http://docs.oasis-open.org/odata/ns/edm'
    }
    entity_sets = parsed_xml.xpath(
      '//edmx:Edmx/edmx:DataServices/edm:Schema/edm:EntityContainer/edm:EntitySet', namespaces
    )
    entity_sets.to_h { |entity_set| [entity_set['Name'], entity_set['EntityType']] }
  end

  def entity_types_from_doc(parsed_xml) # rubocop:disable Metrics/MethodLength
    namespaces = {
      'edmx' => 'http://docs.oasis-open.org/odata/ns/edmx',
      'edm' => 'http://docs.oasis-open.org/odata/ns/edm'
    }

    entity_types = parsed_xml.xpath('//edmx:Edmx/edmx:DataServices/edm:Schema/edm:EntityType',
                                    namespaces)

    entity_types_hash = {}

    entity_types.each do |entity_type|
      entity_name = entity_type['Name']
      properties = entity_type.xpath('edm:Property', namespaces).map do |property|
        {
          name: property['Name'],
          type: property['Type'],
          nullable: property['Nullable']
        }
      end

      keys = entity_type.xpath('edm:Key/edm:PropertyRef', namespaces).map { |key| key['Name'] }

      entity_types_hash[entity_name] = {
        properties: properties,
        keys: keys
      }
    end

    entity_types_hash
  end

  def parse_xml_from_string(string)
    document = Nokogiri.XML(string)
    errors = document.validate
    raise errors if errors

    document
  end
end

Context = Struct.new(:endpoint)

CountryCity = Struct.new(:country_region, :name, :region) do
  def self.all
    [CountryCity.new('country_region', 'name', 'region')]
  end
end

AddressInfo = Struct.new(:address, :city) do
  def self.all
    [AddressInfo.new('address', CountryCity.new('country', 'name', 'region'))]
  end
end

Person = Struct.new(:id, :user_name, :name, :emails, :address_info, :gender, :concurrency) do
  def self.all
    [
      Person.new('1', 'user1', 'User', ['user@email.com'],
                 [AddressInfo.new('address', CountryCity.new('country', 'name', 'region'))],
                 'Male', 11)
    ]
  end
end

RSpec.configure do |config|
  config.include TestHelpers
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = 'doc'
  end
  config.seed = srand % 0xFFFF
end
