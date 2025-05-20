require 'spec_helper'

if Gem.loaded_specs['railties']
  require 'rails/generators'
  require 'generators/odata_duty/install/install_generator'
  require 'fileutils'

  RSpec.describe OdataDuty::Generators::InstallGenerator do
    let(:destination) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(destination, 'config'))
      File.write(File.join(destination, 'config/routes.rb'), "Rails.application.routes.draw do\nend\n")
    end

    after do
      FileUtils.rm_rf(destination)
    end

    it 'creates controller, schema and routes' do
      described_class.start([], destination_root: destination)

      expect(File).to exist(File.join(destination, 'app/controllers/api_controller.rb'))
      expect(File).to exist(File.join(destination, 'app/schemas/schema.rb'))
      routes = File.read(File.join(destination, 'config/routes.rb'))
      expect(routes).to include("scope '/api'")
    end
  end
else
  RSpec.describe 'OdataDuty install generator' do
    it 'skips because Railties is not available' do
      skip 'Railties not installed'
    end
  end
end
