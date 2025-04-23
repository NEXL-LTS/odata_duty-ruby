require 'bundler/setup'
require 'odata_duty'
require 'benchmark/ips'

SampleData = Data.define(:id, :int_val, :string_val, :date_val, :datetime_val, :bool_val)
NestedData = Data.define(:id, :sample1, :sample2)

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

NESTED_DATA = DATA.map do |row|
  NestedData.new(row.id, row, DATA.sample)
end

class NestedSampleResolver < OdataDuty::SetResolver
  def od_after_init
    @records = NESTED_DATA
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

  sample_nested_complex = s.add_complex_type(name: 'SampleNestedComplex') do |et|
    et.property 'int_val', Integer
    et.property 'string_val', String
    et.property 'date_val', Date
    et.property 'datetime_val', DateTime
    et.property 'bool_val', TrueClass
  end
  nested_entity = s.add_entity_type(name: 'NestedEntity') do |et|
    et.property_ref 'id', String
    et.property 'sample1', sample_nested_complex
    et.property 'sample2', sample_nested_complex
  end
  s.add_entity_set(name: 'NestedSamples', url: 'NestedSamples', entity_type: nested_entity,
                   resolver: 'NestedSampleResolver')
end

Context = Struct.new(:endpoint) do
  def url_for(url:, anchor: nil, **params)
    params_joined = params.transform_keys(&:to_s).map { |k, v| "#{k}=#{v}" }.join('&')
    "#{url}#{params_joined == '' ? '' : "?#{params_joined}"}#{anchor ? "##{anchor}" : ''}"
  end
end

def build_sample(data)
  booleans = [true, false, nil]

  { 'int_val' => data.int_val,
    'string_val' => data.string_val,
    'date_val' => data.date_val&.iso8601,
    'datetime_val' => data.datetime_val&.iso8601,
    'bool_val' => booleans.include?(data.bool_val) && data.bool_val }
end

def simple_test(context = Context.new)
  base_url = context.url_for(url: 'NestedSamples')
  result = NESTED_DATA.map do |nested_data|
    { 'id' => nested_data.id,
      'sample1' => build_sample(nested_data.sample1),
      'sample2' => build_sample(nested_data.sample2),
      '@odata.id' => "http://localhost/#{base_url}('#{nested_data.id}')" }
  end
  Oj.dump('value' => result, mode: :compat)
end

Benchmark.ips do |x|
  x.report('simple') do
    simple_test
  end
  x.report('odata-duty') do
    schema.execute('NestedSamples', context: Context.new)
  end

  x.compare!
end

# require 'vernier'

# Vernier.profile(out: 'odata_profile.json') do
#   schema.execute('NestedSamples', context: Context.new)
# end

# Vernier.profile(out: 'simple_profile.json') do
#   simple_test
# end

simple_json = Oj.load(simple_test)
odata_json = Oj.load(schema.execute('NestedSamples', context: Context.new))

if simple_json.fetch('value') == odata_json.fetch('value')
  puts 'Both results are the same'
else
  puts simple_json.fetch('value').first
  puts odata_json.fetch('value').first
  raise 'Results are different'
end
