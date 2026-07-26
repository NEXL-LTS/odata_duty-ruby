require 'erb'

module OdataDuty
  module EdmxSchema
    def self.index_hash(schema)
      {
        '@odata.context': [schema.base_url.chomp('/'), '$metadata'].join('/'),
        value: schema.endpoints.map do |e|
          { name: e.name, kind: 'EntitySet', url: e.url }
        end
      }
    end

    def self.metadata_xml(metadata)
      b = binding
      ERB.new(File.read("#{__dir__}/../metadata.xml.erb")).result(b)
    end
  end
end
