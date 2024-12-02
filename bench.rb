require 'bundler/setup'
require 'odata_duty'
require 'benchmark/ips'

SampleData = Data.define(:id, :int_val, :string_val, :date_val, :datetime_val, :bool_val)

DATA = 1000.times.map do |i|
  SampleData.new("string_val_#{i}", i, "string_val_#{i}", Date.today, DateTime.now, i.even?)
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

Benchmark.ips do |x|
  x.report('simple') do
    context = Context.new
    result = DATA.each do |data|
      {
        id: data.id,
        int_val: data.int_val,
        string_val: data.string_val,
        date_val: data.date_val.iso8601,
        datetime_val: data.datetime_val.iso8601,
        bool_val: data.bool_val,
        '@odata.id': context.url_for(url: 'Samples', id: data.id)
      }
    end
    Oj.dump(result)
  end
  x.report('odata-duty') do
    schema.execute('Samples', context: Context.new)
  end

  x.compare!
end

# require 'vernier'

# Vernier.profile(out: "time_profile.json") do
#   schema.execute('Samples', context: Context.new)
# end
