# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'odata_duty'
  spec.version       = '0.6.0'
  spec.authors       = ['Grant Petersen-Speelman']
  spec.email         = ['grant@nexl.io']

  spec.summary       = 'Write OData compatible APIs'
  spec.description   =
    'Write OData compatible APIs to easier connection to Microsoft PowerBI and PowerAutomate.'
  # spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.required_ruby_version = Gem::Requirement.new('>= 3.0.0')

  spec.metadata['homepage_uri'] = 'https://github.com/NEXL-LTS/odata_duty-ruby'
  spec.metadata['source_code_uri'] = 'https://github.com/NEXL-LTS/odata_duty-ruby'
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir['CHANGELOG.md', 'lib/**/*', 'LICENSE.txt', 'README.md'].to_a
  spec.bindir = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'oj', '>= 3.0.0', '< 5.0.0'

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata = {
    'rubygems_mfa_required' => 'true'
  }
end
