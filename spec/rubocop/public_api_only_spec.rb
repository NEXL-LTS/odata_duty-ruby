require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../rubocop/cop/odata_duty/public_api_only'

RSpec.describe RuboCop::Cop::OdataDuty::PublicApiOnly, :config do
  let(:config) do
    RuboCop::Config.new(
      'OdataDuty/PublicApiOnly' => {
        'Namespace' => 'OdataDuty',
        'AllowedConstants' => %w[
          OdataDuty::EntitySet
          OdataDuty::Schema
        ],
        'AllowedConstantPatterns' => [
          '\AOdataDuty::\w*Error\z',
          '\AOdataDuty::Invalid\w+\z'
        ]
      }
    )
  end

  describe 'internal constants' do
    it 'accepts an allowlisted constant' do
      expect_no_offenses(<<~RUBY)
        class PeopleSet < OdataDuty::EntitySet; end
      RUBY
    end

    it 'accepts a constant matched by the Error pattern' do
      expect_no_offenses(<<~RUBY)
        expect { subject }.to raise_error(OdataDuty::ResourceNotFoundError)
      RUBY
    end

    it 'accepts a constant matched by the Invalid pattern' do
      expect_no_offenses(<<~RUBY)
        expect { subject }.to raise_error(OdataDuty::InvalidType)
      RUBY
    end

    it 'accepts a top-level constant outside the namespace' do
      expect_no_offenses(<<~RUBY)
        PeopleSet.new
      RUBY
    end

    it 'flags an internal constant that is the whole expression (nil parent)' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor
        ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags an internal constant' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor.execute(url: url, schema: schema)
        ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a nested constant under an allowlisted parent exactly once' do
      expect_offense(<<~RUBY)
        OdataDuty::Schema::Metadata.new(schema)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `OdataDuty::Schema::Metadata` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags an internal constant used as a nested namespace parent' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor::Inner.new
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor::Inner` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end

  describe 'internal methods' do
    it 'flags a __-prefixed method with a receiver' do
      expect_offense(<<~RUBY)
        schema.__metadata.entity_sets
               ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a __-prefixed method with no receiver' do
      expect_offense(<<~RUBY)
        __load(schema)
        ^^^^^^ `__load` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a __-prefixed method called with safe navigation' do
      expect_offense(<<~RUBY)
        schema&.__metadata
                ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end
  end

  describe 'visibility bypass' do
    it 'flags send' do
      expect_offense(<<~RUBY)
        set.send(:converted_id, '1')
            ^^^^ `send` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_variable_get' do
      expect_offense(<<~RUBY)
        set.instance_variable_get(:@records)
            ^^^^^^^^^^^^^^^^^^^^^ `instance_variable_get` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_variable_set' do
      expect_offense(<<~RUBY)
        set.instance_variable_set(:@records, [])
            ^^^^^^^^^^^^^^^^^^^^^ `instance_variable_set` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_eval' do
      expect_offense(<<~RUBY)
        set.instance_eval { @records }
            ^^^^^^^^^^^^^ `instance_eval` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags const_get' do
      expect_offense(<<~RUBY)
        Object.const_get('OdataDuty::Executor')
               ^^^^^^^^^ `const_get` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags method' do
      expect_offense(<<~RUBY)
        set.method(:converted_id)
            ^^^^^^ `method` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags __send__ exactly once' do
      expect_offense(<<~RUBY)
        set.__send__(:converted_id)
            ^^^^^^^^ `__send__` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'accepts public_send' do
      expect_no_offenses(<<~RUBY)
        record.public_send(property_name)
      RUBY
    end
  end

  describe 'mocking gem behaviour' do
    it 'flags expect_any_instance_of' do
      expect_offense(<<~RUBY)
        expect_any_instance_of(PeopleSet).to receive(:od_select)
        ^^^^^^^^^^^^^^^^^^^^^^ `expect_any_instance_of` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end

    it 'flags allow_any_instance_of' do
      expect_offense(<<~RUBY)
        allow_any_instance_of(PeopleSet).to receive(:od_select)
        ^^^^^^^^^^^^^^^^^^^^^ `allow_any_instance_of` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end

    it 'flags stub_const' do
      expect_offense(<<~RUBY)
        stub_const('OdataDuty::Executor', fake)
        ^^^^^^^^^^ `stub_const` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end
  end

  describe 'configuration defaults' do
    let(:config) do
      RuboCop::Config.new(
        'OdataDuty/PublicApiOnly' => {
          'AllowedConstants' => %w[OdataDuty::EntitySet],
          'AllowedConstantPatterns' => []
        }
      )
    end

    it 'defaults the namespace to OdataDuty when no Namespace key is set' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor.execute
        ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end
end
