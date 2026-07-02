require 'spec_helper'

class ExecCovEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class ExecCovSet < OdataDuty::EntitySet
  entity_type ExecCovEntity

  RECORDS = (1..5).map { |i| OpenStruct.new(id: i.to_s, name: "n#{i}") }

  def od_after_init
    @records = RECORDS
  end

  def od_top(top)
    @records = @records[0, top.to_i]
  end

  def od_skip(skip)
    @records = @records[skip.to_i..] || []
  end

  def od_skiptoken(skiptoken)
    @records = @records[skiptoken.to_i..] || []
  end

  def od_search(_expression)
    @records = []
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end

  def delete(id)
    OpenStruct.new(deleted: id)
  end
end

class ExecCovSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ExecCovSet]
end

RSpec.describe OdataDuty::EntitySet, 'executor query option handling' do
  subject(:schema) { ExecCovSchema }

  def collection(query_options)
    Oj.load(schema.execute('ExecCov', context: Context.new, query_options: query_options))
  end

  it 'applies a supported $skip' do
    expect(collection('$skip' => '4')['value'].size).to eq(1)
  end

  it 'applies a supported $top' do
    expect(collection('$top' => '2')['value'].size).to eq(2)
  end

  it 'applies a supported $skiptoken' do
    expect(collection(:$skiptoken => '3')['value'].size).to eq(2)
  end

  it 'applies a supported $search' do
    expect(collection('$search' => 'anything')['value']).to eq([])
  end

  it 'ignores a nil-valued $top' do
    expect(collection('$top' => nil)['value'].size).to eq(5)
  end

  it 'ignores a nil-valued $skip' do
    expect(collection('$skip' => nil)['value'].size).to eq(5)
  end

  it 'ignores a nil-valued $skiptoken' do
    expect(collection(:$skiptoken => nil)['value'].size).to eq(5)
  end

  it 'ignores a nil-valued $search' do
    expect(collection('$search' => nil)['value'].size).to eq(5)
  end

  it 'raises for an unknown endpoint' do
    expect do
      schema.execute('NoSuchEndpoint', context: Context.new)
    end.to raise_error(OdataDuty::UnknownPropertyError, /No endpoint/)
  end

  it 'raises ResourceNotFoundError when individual returns nil' do
    expect do
      schema.execute("ExecCov('999')", context: Context.new)
    end.to raise_error(OdataDuty::ResourceNotFoundError, /No such entity/)
  end

  it 'passes a nil id to delete when the url has no bracketed id' do
    json = schema.delete('ExecCov', context: Context.new)
    expect(json).to include('@odata.context')
  end
end
