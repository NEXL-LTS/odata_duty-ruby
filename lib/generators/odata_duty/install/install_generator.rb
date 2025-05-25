module OdataDuty
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      class_option :module, type: :string, default: nil, desc: 'Module namespace'

      def create_controller
        template 'controller.rb.tt',
                 File.join('app/controllers', controller_path, 'api_controller.rb')
      end

      def create_schema
        template 'schema.rb.tt', File.join('app/schemas', controller_path, 'schema.rb')
      end

      def add_routes
        route route_contents
      end

      private

      def controller_path
        options[:module]&.underscore || ''
      end

      def module_name
        options[:module]&.camelize
      end

      def controller_class
        [module_name, 'ApiController'].compact.join('::')
      end

      def schema_class
        [module_name, 'Schema'].compact.join('::')
      end

      def route_controller
        parts = []
        parts << controller_path unless controller_path.empty?
        parts << 'api'
        parts.join('/')
      end

      def route_contents
        <<~RUBY
          scope '/api' do
            root '#{route_controller}#index'
            get '$metadata' => '#{route_controller}#metadata'
            get '$oas2' => '#{route_controller}#oas2'
            get '*url' => '#{route_controller}#show'
            post '*url' => '#{route_controller}#create'
          end
        RUBY
      end
    end
  end
end
