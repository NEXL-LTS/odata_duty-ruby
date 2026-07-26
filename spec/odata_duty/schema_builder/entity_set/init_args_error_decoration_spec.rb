require 'spec_helper'

class MismatchInitResolver < OdataDuty::SetResolver
  def od_after_init(required); end

  def collection
    []
  end
end

class GenericInitErrorResolver < OdataDuty::SetResolver
  def od_after_init
    raise 'boom during init'
  end

  def collection
    []
  end
end

class SwallowsArgumentErrorResolver < OdataDuty::SetResolver
  def od_after_init
    @records = build_records
  end

  def build_records
    [].fetch
  end

  def collection
    @records
  end
end

class ArgumentErrorInsideAfterInitResolver < OdataDuty::SetResolver
  def od_after_init
    Integer('not-a-number')
  end

  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'decorates od_after_init init-args errors' do
    let(:call_sites) { {} }

    subject(:schema) do
      sites = call_sites
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'InitDecoration') do |et|
          et.property_ref 'id', String
        end

        sites[:mismatch] = "#{__FILE__}:#{__LINE__ + 1}"
        s.add_entity_set(name: 'Mismatch', entity_type: entity,
                         resolver: 'MismatchInitResolver')
        sites[:generic] = "#{__FILE__}:#{__LINE__ + 1}"
        s.add_entity_set(name: 'Generic', entity_type: entity,
                         resolver: 'GenericInitErrorResolver')
        s.add_entity_set(name: 'SwallowsArgumentError', entity_type: entity,
                         resolver: 'SwallowsArgumentErrorResolver')
        s.add_entity_set(name: 'ArgumentErrorInside', entity_type: entity,
                         resolver: 'ArgumentErrorInsideAfterInitResolver')
      end
    end

    def raised_from(path)
      schema.execute(path, context: Context.new)
      nil
    rescue StandardError => e
      e
    end

    describe 'when od_after_init signature does not match the init args' do
      it 'raises InitArgsMismatchError' do
        raised = raised_from('Mismatch')
        expect(raised).to be_a(OdataDuty::InitArgsMismatchError)
        expect(raised.message).to eq('wrong number of arguments (given 0, expected 1)')
      end

      it 'inserts the add_entity_set location at backtrace index 1' do
        raised = raised_from('Mismatch')
        location = MismatchInitResolver.instance_method(:od_after_init).source_location.join(':')
        expect(raised.backtrace[0]).to start_with(location)
        expect(raised.backtrace[0]).to include("od_after_init'")
        expect(raised.backtrace[1]).to start_with(call_sites.fetch(:mismatch))
      end
    end

    describe 'when od_after_init raises a non-argument error' do
      it 'preserves the original error class' do
        raised = raised_from('Generic')
        expect(raised).to be_a(RuntimeError)
        expect(raised).not_to be_a(OdataDuty::InitArgsMismatchError)
        expect(raised.message).to eq('boom during init')
      end

      it 'inserts the add_entity_set location at backtrace index 2' do
        raised = raised_from('Generic')
        expect(raised.backtrace[0]).to include("od_after_init'")
        expect(raised.backtrace[1]).not_to start_with(call_sites.fetch(:generic))
        expect(raised.backtrace[2]).to start_with(call_sites.fetch(:generic))
      end
    end

    describe 'when an ArgumentError originates below od_after_init' do
      it 'is not swallowed into InitArgsMismatchError' do
        raised = raised_from('SwallowsArgumentError')
        expect(raised).to be_a(ArgumentError)
        expect(raised).not_to be_a(OdataDuty::InitArgsMismatchError)
      end
    end

    describe 'when od_after_init directly triggers an ArgumentError' do
      it 'is not swallowed into InitArgsMismatchError' do
        raised = raised_from('ArgumentErrorInside')
        expect(raised).to be_a(ArgumentError)
        expect(raised).not_to be_a(OdataDuty::InitArgsMismatchError)
      end
    end
  end
end
