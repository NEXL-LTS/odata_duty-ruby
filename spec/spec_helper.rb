require 'byebug'
require 'nokogiri'
require 'odata_duty'

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

Context = Struct.new(:endpoint) do
  def url_for(url:, anchor: nil, **params)
    params_joined = params.transform_keys(&:to_s).map { |k, v| "#{k}=#{v}" }.join('&')
    "#{url}#{params_joined == '' ? '' : "?#{params_joined}"}#{anchor ? "##{anchor}" : ''}"
  end
end

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
end
