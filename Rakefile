# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

task :enforce_coverage do
  ENV['COVERAGE_ENFORCE'] = 'true'
end

RSpec::Core::RakeTask.new(:spec)
task spec: :enforce_coverage

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]
