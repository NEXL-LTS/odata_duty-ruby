require 'spec_helper'

class GatingHookfulResolver < OdataDuty::SetResolver
  ALL_RECORDS = (1..5).map { |i| OpenStruct.new(id: i.to_s) }

  def od_after_init
    @records = ALL_RECORDS
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
end

class GatingHooklessResolver < OdataDuty::SetResolver
  ALL_RECORDS = (1..5).map { |i| OpenStruct.new(id: i.to_s) }

  def od_after_init
    @records = ALL_RECORDS
  end

  def collection
    @records
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'query-option gating' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        entity = s.add_entity_type(name: 'GatingTest') do |et|
          et.property_ref 'id', String
        end

        s.add_entity_set(name: 'Hookful', entity_type: entity,
                         resolver: 'GatingHookfulResolver')
        s.add_entity_set(name: 'Hookless', entity_type: entity,
                         resolver: 'GatingHooklessResolver')
      end
    end

    def hookful(query_options)
      Oj.load(schema.execute('Hookful', context: Context.new, query_options: query_options))
    end

    def hookless(query_options)
      Oj.load(schema.execute('Hookless', context: Context.new, query_options: query_options))
    end

    it 'applies $top when od_top is present' do
      expect(hookful('$top' => '2')['value'].size).to eq(2)
    end

    it 'applies $skip when od_skip is present' do
      expect(hookful('$skip' => '4')['value'].size).to eq(1)
    end

    it 'applies $skiptoken when od_skiptoken is present' do
      expect(hookful(:$skiptoken => '3')['value'].size).to eq(2)
    end

    it 'applies $search when od_search is present' do
      expect(hookful('$search' => 'anything')['value']).to eq([])
    end

    it 'raises the exact message for $top when od_top is absent' do
      expect do
        hookless('$top' => '2')
      end.to raise_error(OdataDuty::NoImplementationError,
                         '$top not implemented for GatingHooklessResolver')
    end

    it 'raises the exact message for $skip when od_skip is absent' do
      expect do
        hookless('$skip' => '2')
      end.to raise_error(OdataDuty::NoImplementationError,
                         '$skip not implemented for GatingHooklessResolver')
    end

    it 'raises the exact message for $skiptoken when od_skiptoken is absent' do
      expect do
        hookless(:$skiptoken => '2')
      end.to raise_error(OdataDuty::NoImplementationError,
                         '$skiptoken not implemented for GatingHooklessResolver')
    end

    it 'raises the exact message for $search when od_search is absent' do
      expect do
        hookless('$search' => 'x')
      end.to raise_error(OdataDuty::NoImplementationError,
                         '$search not implemented for GatingHooklessResolver')
    end

    it 'does not raise for a plain request on a resolver lacking the hooks' do
      expect(hookless({})['value'].size).to eq(5)
    end

    it 'ignores a nil-valued $top on a resolver lacking od_top' do
      expect(hookless('$top' => nil)['value'].size).to eq(5)
    end

    it 'ignores a nil-valued $skip on a resolver lacking od_skip' do
      expect(hookless('$skip' => nil)['value'].size).to eq(5)
    end

    it 'ignores a nil-valued $skiptoken on a resolver lacking od_skiptoken' do
      expect(hookless(:$skiptoken => nil)['value'].size).to eq(5)
    end

    it 'ignores a nil-valued $search on a resolver lacking od_search' do
      expect(hookless('$search' => nil)['value'].size).to eq(5)
    end

    it 'does not call od_search when $search is absent (would empty the collection)' do
      expect(hookful({})['value'].size).to eq(5)
    end

    it 'does not call od_top when only $skip is present' do
      expect(hookful('$skip' => '1')['value'].size).to eq(4)
    end

    it 'ignores a non-$ query option' do
      expect(hookful('top' => '2')['value'].size).to eq(5)
    end

    it 'applies query options on an individual request, raising for an unsupported $top' do
      expect do
        schema.execute("Hookless('1')", context: Context.new, query_options: { '$top' => '2' })
      end.to raise_error(OdataDuty::NoImplementationError,
                         '$top not implemented for GatingHooklessResolver')
    end

    it 'raises InvalidQueryOptionError for a negative $top' do
      expect do
        hookful('$top' => '-1')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$top' must be a non-negative integer, got '-1'")
    end

    it 'raises InvalidQueryOptionError for a negative $skip' do
      expect do
        hookful('$skip' => '-1')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$skip' must be a non-negative integer, got '-1'")
    end

    it 'raises InvalidQueryOptionError for a non-numeric $top' do
      expect do
        hookful('$top' => 'abc')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$top' must be a non-negative integer, got 'abc'")
    end

    it 'raises InvalidQueryOptionError for a decimal $top' do
      expect do
        hookful('$top' => '1.5')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$top' must be a non-negative integer, got '1.5'")
    end

    it 'raises InvalidQueryOptionError for an empty-string $top' do
      expect do
        hookful('$top' => '')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$top' must be a non-negative integer, got ''")
    end

    it 'treats a leading-zero $top as decimal, not octal' do
      expect(hookful('$top' => '010')['value'].size).to eq(5)
    end

    it 'accepts a leading-zero $top with an invalid-octal digit, proving base-10 parsing' do
      expect(hookful('$top' => '018')['value'].size).to eq(5)
    end

    it 'raises InvalidQueryOptionError before checking for od_top support' do
      expect do
        hookless('$top' => '-1')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$top' must be a non-negative integer, got '-1'")
    end

    it 'raises InvalidQueryOptionError before checking for od_skip support' do
      expect do
        hookless('$skip' => '-1')
      end.to raise_error(OdataDuty::InvalidQueryOptionError,
                         "'$skip' must be a non-negative integer, got '-1'")
    end

    it 'accepts a $top of 0 as valid, yielding an empty value array' do
      expect(hookful('$top' => '0')['value']).to eq([])
    end

    it 'accepts a $skip of 0 as valid, yielding the full value array' do
      expect(hookful('$skip' => '0')['value'].size).to eq(5)
    end

    it 'applies $top and $skip together in one request' do
      expect(hookful('$skip' => '1', '$top' => '2')['value'].map { |r| r['id'] })
        .to eq(%w[2 3])
    end
  end
end
