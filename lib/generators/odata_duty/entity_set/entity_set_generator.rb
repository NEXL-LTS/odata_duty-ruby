require 'rails/generators'

module OdataDuty
  module Generators
    # EntitySetGenerator creates OData entity types and sets
    class EntitySetGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      argument :attributes, type: :array, default: [], banner: 'field:type field:type'

      class_option :skip_tests, type: :boolean, default: false, desc: 'Skip test file generation'

      def create_entity_type
        template 'entity_type.rb.erb', File.join('app/odata', "#{file_name}_entity.rb")
      end

      def create_active_record_concern
        template 'odata_active_record_concern.rb.erb',
                 File.join('app/odata', 'odata_active_record_concern.rb')
      end

      def create_entity_set
        template 'entity_set.rb.erb', File.join('app/odata', "#{file_name}_set.rb")
      end

      def create_tests
        return if options[:skip_tests]

        template 'entity_type_spec.rb.erb', File.join('spec/odata', "#{file_name}_entity_spec.rb")
        template 'entity_set_spec.rb.erb', File.join('spec/odata', "#{file_name}_set_spec.rb")
      end

      private

      def attribute_type_map
        {
          'string' => 'String',
          'text' => 'String',
          'integer' => 'Integer',
          'int' => 'Integer',
          'datetime' => 'Time',
          'timestamp' => 'Time',
          'time' => 'Time',
          'date' => 'Date',
          'boolean' => 'TrueClass',
          'bool' => 'TrueClass'
        }
      end

      def odata_type(type)
        type_key = type.to_s.downcase
        attribute_type_map.fetch(type_key, 'String')
      end
    end
  end
end
