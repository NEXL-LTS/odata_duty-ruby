#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'odata_duty'

require 'rails/generators'
require 'generators/odata_duty/entity_set/entity_set_generator'
require 'fileutils'
require 'tmpdir'

# Create a temporary directory for testing
destination = Dir.mktmpdir
puts "Using temp directory: #{destination}"

begin
  FileUtils.mkdir_p(File.join(destination, 'app/odata'))
  FileUtils.mkdir_p(File.join(destination, 'spec/odata'))
  
  # Run the generator with a namespaced model
  puts "Running generator for Admin::Product..."
  OdataDuty::Generators::EntitySetGenerator.start(
    ['Admin::Product', 'id:string', 'name:string', 'price:decimal'],
    destination_root: destination
  )
  
  # Check the created files
  puts "\nCreated files:"
  Dir.glob("#{destination}/**/*").each do |path|
    next if File.directory?(path)
    puts path
    puts "---"
    puts File.read(path)[0..500] # Show first 500 chars of each file
    puts "\n---\n"
  end
ensure
  # Clean up
  FileUtils.rm_rf(destination)
end
