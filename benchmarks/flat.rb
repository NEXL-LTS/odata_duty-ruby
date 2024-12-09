require 'bundler/setup'
require 'odata_duty'
require 'benchmark/ips'

SampleData = Data.define(:id, :int_val, :string_val, :date_val, :datetime_val, :bool_val)

DATA = 5000.times.map do |i|
  if (i % 3).zero?
    SampleData.new("string_val_#{i}",
                   nil,
                   nil,
                   nil,
                   nil,
                   nil)
  else
    SampleData.new("string_val_#{i}",
                   i,
                   "string_val_#{i}",
                   Date.today,
                   DateTime.now,
                   i.even?)
  end
end

class SampleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = DATA
  end

  def count
    @records.count
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |record| record.id == id }
  end
end

schema = OdataDuty::SchemaBuilder.build(namespace: 'SampleData', scheme: 'http', host: 'localhost',
                                        base_path: '/') do |s|
  s.version = '1.2.3'
  s.title = 'This is a sample OData service.'
  sample_entity = s.add_entity_type(name: 'SampleEntity') do |et|
    et.property_ref 'id', String
    et.property 'int_val', Integer
    et.property 'string_val', String
    et.property 'date_val', Date
    et.property 'datetime_val', DateTime
    et.property 'bool_val', TrueClass
  end

  s.add_entity_set(name: 'Samples', url: 'Samples', entity_type: sample_entity,
                   resolver: 'SampleResolver')
end

Context = Struct.new(:endpoint) do
  def url_for(url:, anchor: nil, **params)
    params_joined = params.transform_keys(&:to_s).map { |k, v| "#{k}=#{v}" }.join('&')
    "#{url}#{params_joined == '' ? '' : "?#{params_joined}"}#{anchor ? "##{anchor}" : ''}"
  end
end

BOOLEANS = [true, false, nil].freeze

def simple_test(context = Context.new)
  base_url = context.url_for(url: 'Samples')
  result = DATA.map do |data|
    { 'id' => data.id, 'int_val' => data.int_val&.to_int,
      'string_val' => data.string_val&.to_str, 'date_val' => data.date_val&.iso8601,
      'datetime_val' => data.datetime_val&.iso8601,
      'bool_val' => BOOLEANS.include?(data.bool_val) && data.bool_val,
      '@odata.id' => "#{base_url}('#{data.id}')" }
  end
  Oj.dump('value' => result, mode: :compat)
end

Benchmark.ips do |x|
  x.report('simple') do
    simple_test
  end
  x.report('odata-duty') do
    schema.execute('Samples', context: Context.new)
  end

  x.compare!
end

# require 'vernier'

# Vernier.profile(out: 'odata_profile.json') do
#   schema.execute('Samples', context: Context.new)
# end

# Vernier.profile(out: 'simple_profile.json') do
#   simple_test
# end

simple_json = Oj.load(simple_test)
odata_json = Oj.load(schema.execute('Samples', context: Context.new))

if simple_json.fetch('value') == odata_json.fetch('value')
  puts 'Both results are the same'
else
  puts simple_json.fetch('value').first
  puts odata_json.fetch('value').first
  raise 'Results are different'
end
