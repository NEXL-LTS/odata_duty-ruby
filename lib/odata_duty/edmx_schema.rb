module OdataDuty
  module EdmxSchema
    def self.index_hash(schema)
      {
        '@odata.context': [schema.base_url.chomp('/'), '$metadata'].join('/'),
        value: schema.endpoints.map do |e|
          { name: e.name, kind: e.kind, url: e.url }
        end
      }
    end

    def self.metadata_xml(metadata)
      require 'erb'

      b = binding
      # create and run templates, filling member data variables
      erb = ERB.new(File.read("#{__dir__}/../metadata.xml.erb"), trim_mode: '<>')
      erb.location = ["#{__dir__}/../metadata.xml.erb", 1]
      erb.result b
    end
  end
end
