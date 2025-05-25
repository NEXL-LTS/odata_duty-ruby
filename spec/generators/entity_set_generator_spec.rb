require 'spec_helper'

if Gem.loaded_specs['railties']
  require 'rails/generators'
  require 'generators/odata_duty/entity_set/entity_set_generator'
  require 'fileutils'
  require 'tmpdir'

  RSpec.describe OdataDuty::Generators::EntitySetGenerator do
    let(:destination) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(destination, 'app/odata'))
      FileUtils.mkdir_p(File.join(destination, 'spec/odata'))
    end

    after do
      FileUtils.rm_rf(destination)
    end

    def validate_ruby_syntax(file_path)
      `ruby -c "#{file_path}" 2>&1`.tap do |output|
        expect(output).to include('Syntax OK'), "#{file_path} has invalid syntax: #{output}"
      end
    end

    it 'creates entity set files with attributes and active record concern' do
      described_class.start(
        ['Person', 'name:string', 'age:integer', 'active:boolean', 'created_on:date',
         'access_at:time'],
        destination_root: destination
      )

      # Check if the files were created
      entity_type_path = File.join(destination, 'app/odata/person_entity.rb')
      entity_set_path = File.join(destination, 'app/odata/person_set.rb')
      entity_type_spec_path = File.join(destination, 'spec/odata/person_entity_spec.rb')
      entity_set_spec_path = File.join(destination, 'spec/odata/person_set_spec.rb')
      active_record_concern_path = File.join(destination,
                                             'app/odata/odata_active_record_concern.rb')

      # Check that the concern file was created
      expect(File).to exist(active_record_concern_path)

      # Check contents of the entity type file
      entity_type_content = File.read(entity_type_path)
      expect(entity_type_content).to include("property_ref 'name', String, nullable: false")
      expect(entity_type_content).to include("property 'age', Integer")
      expect(entity_type_content).to include("property 'active', TrueClass")
      expect(entity_type_content).to include("property 'created_on', Date")
      expect(entity_type_content).to include("property 'access_at', Time")

      # Check that entity_set includes the concern
      entity_set_content = File.read(entity_set_path)
      expect(entity_set_content).to include('include OdataActiveRecordConcern')

      # Validate Ruby syntax
      validate_ruby_syntax(entity_type_path)
      validate_ruby_syntax(entity_set_path)
      validate_ruby_syntax(entity_type_spec_path)
      validate_ruby_syntax(entity_set_spec_path)
      validate_ruby_syntax(active_record_concern_path)
    end

    it 'creates entity set files without tests when skip_tests is specified' do
      described_class.start(['Product', 'name:string', 'price:decimal', '--skip-tests'],
                            destination_root: destination)

      # Check if the main files were created
      entity_type_path = File.join(destination, 'app/odata/product_entity.rb')
      entity_set_path = File.join(destination, 'app/odata/product_set.rb')

      validate_ruby_syntax(entity_type_path)
      validate_ruby_syntax(entity_set_path)

      # Check that test files were not created
      expect(File).not_to exist(File.join(destination, 'spec/odata/product_entity_spec.rb'))
      expect(File).not_to exist(File.join(destination, 'spec/odata/product_set_spec.rb'))
    end
  end
else
  RSpec.describe 'OdataDuty entity set generator' do
    it 'skips because Railties is not available' do
      skip 'Railties not installed'
    end
  end
end
