require 'spec_helper'
require 'forwardable'

class BuilderVisiblePeopleContext
  def initialize(*people)
    @people = people
  end

  def visible_people
    @people
  end
end

class BuilderRailsLikeParams
  extend Forwardable

  def_delegators :@hash, :[], :key?, :except, :merge

  def initialize(hash)
    @hash = hash
  end

  def to_h
    @hash.dup
  end
end

module BuilderContextProbeCollection
  def collection
    [OpenStruct.new(id: '1', value: probe.to_s)]
  end
end

class BuilderDelegationProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    context.visible_people.join(',')
  end
end

class BuilderFullUrlPlainProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    "#{context.od_full_url('People')}|#{context.od_full_url('People').is_a?(String)}"
  end
end

class BuilderFullUrlQueryProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    context.od_full_url('People', top: 5)
  end
end

class BuilderFullUrlAnchorProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    context.od_full_url('$metadata', anchor: 'People')
  end
end

class BuilderQueryOptionsProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def od_top(top); end

  def probe
    matches = context.query_options == { '$top' => '1' }
    "#{matches}|#{context.query_options.instance_of?(Hash)}"
  end
end

class BuilderBaseUrlProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    context.base_url
  end
end

class BuilderCurrentProbeResolver < OdataDuty::SetResolver
  include BuilderContextProbeCollection

  def probe
    empty = context.current == {}
    first_id = context.current.object_id
    context.current['k'] ||= 'memoized'
    same = first_id == context.current.object_id && context.current['k'] == 'memoized'
    "empty=#{empty}|same=#{same}"
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'exposes a request-context object to hooks' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'example.org', scheme: 'https',
                          base_path: '/odata') do |s|
        entity_type = s.add_entity_type(name: 'ContextProbe') do |et|
          et.property_ref 'id', String
          et.property 'value', String
        end
        {
          'DelegationProbe' => 'BuilderDelegationProbeResolver',
          'FullUrlPlainProbe' => 'BuilderFullUrlPlainProbeResolver',
          'FullUrlQueryProbe' => 'BuilderFullUrlQueryProbeResolver',
          'FullUrlAnchorProbe' => 'BuilderFullUrlAnchorProbeResolver',
          'QueryOptionsProbe' => 'BuilderQueryOptionsProbeResolver',
          'BaseUrlProbe' => 'BuilderBaseUrlProbeResolver',
          'CurrentProbe' => 'BuilderCurrentProbeResolver'
        }.each do |name, resolver|
          s.add_entity_set(name: name, entity_type: entity_type, resolver: resolver)
        end
      end
    end

    let(:ctx) { BuilderVisiblePeopleContext.new('Alice', 'Bob') }
    let(:query_options) { {} }

    def probe_value(set_name)
      json = schema.execute(set_name, context: ctx, query_options: query_options)
      Oj.load(json)['value'].first['value']
    end

    it 'delegates method calls on context to the caller-supplied context object' do
      expect(probe_value('DelegationProbe')).to eq('Alice,Bob')
    end

    describe 'od_full_url' do
      it 'joins base URL and path, returning a String' do
        expect(probe_value('FullUrlPlainProbe'))
          .to eq('https://example.org/odata/People|true')
      end

      it 'appends www-form-encoded query params' do
        expect(probe_value('FullUrlQueryProbe')).to eq('https://example.org/odata/People?top=5')
      end

      it 'appends an anchor fragment' do
        expect(probe_value('FullUrlAnchorProbe'))
          .to eq('https://example.org/odata/$metadata#People')
      end
    end

    describe 'query_options' do
      let(:query_options) { BuilderRailsLikeParams.new({ '$top' => '1' }) }

      it 'normalizes a #to_h-able params object to a plain Hash' do
        expect(probe_value('QueryOptionsProbe')).to eq('true|true')
      end
    end

    it 'exposes base_url with no trailing slash' do
      expect(probe_value('BaseUrlProbe')).to eq('https://example.org/odata')
    end

    it 'exposes current as a per-request memo Hash, empty and stable across calls' do
      expect(probe_value('CurrentProbe')).to eq('empty=true|same=true')
    end
  end
end
