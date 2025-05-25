require 'rails/railtie'

module OdataDuty
  class Railtie < Rails::Railtie
    # Auto-load generators
    generators do
      require 'generators/odata_duty/install/install_generator'
      require 'generators/odata_duty/entity_set/entity_set_generator'
    end
  end
end
