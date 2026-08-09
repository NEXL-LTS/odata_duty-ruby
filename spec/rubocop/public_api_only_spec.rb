require 'spec_helper'
require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../rubocop/cop/odata_duty/public_api_only'

RSpec.describe RuboCop::Cop::OdataDuty::PublicApiOnly, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) do
    RuboCop::Config.new(
      'OdataDuty/PublicApiOnly' => {
        'Namespace' => 'OdataDuty',
        'AllowedConstants' => %w[
          OdataDuty::EntitySet OdataDuty::Schema OdataDuty::SchemaBuilder
        ],
        'AllowedConstantPatterns' => ['\AOdataDuty::\w*Error\z', '\AOdataDuty::Invalid\w+\z']
      }
    )
  end

  describe 'internal constants' do
    it 'accepts an allowlisted base class' do
      expect_no_offenses(<<~RUBY)
        class MySet < OdataDuty::EntitySet; end
      RUBY
    end

    it 'accepts a constant matching the Error pattern' do
      expect_no_offenses(<<~RUBY)
        expect { run }.to raise_error(OdataDuty::ResourceNotFoundError)
      RUBY
    end

    it 'accepts a constant matching the Invalid pattern' do
      expect_no_offenses(<<~RUBY)
        expect { run }.to raise_error(OdataDuty::InvalidType)
      RUBY
    end

    it 'accepts a constant not under the namespace' do
      expect_no_offenses(<<~RUBY)
        Oj.load(body)
      RUBY
    end

    it 'accepts the bare namespace module itself' do
      expect_no_offenses(<<~RUBY)
        OdataDuty
      RUBY
    end

    it 'flags an internal constant under the namespace' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor.new
        ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a nested internal constant exactly once' do
      expect_offense(<<~RUBY)
        OdataDuty::Schema::Metadata
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `OdataDuty::Schema::Metadata` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a constant whose parent is not a const node' do
      expect_offense(<<~RUBY)
        foo(OdataDuty::Executor)
            ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end

  describe 'internal methods' do
    it 'flags a __-prefixed method with a receiver' do
      expect_offense(<<~RUBY)
        schema.__metadata
               ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a receiver-less __-prefixed method' do
      expect_offense(<<~RUBY)
        __metadata
        ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags a __-prefixed method with a safe navigation receiver' do
      expect_offense(<<~RUBY)
        schema&.__metadata
                ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'accepts Ruby built-in __dir__ used to locate fixtures' do
      expect_no_offenses(<<~'RUBY')
        File.read("#{__dir__}/metadata.xml")
      RUBY
    end
  end

  describe 'visibility bypasses' do
    it 'accepts public_send' do
      expect_no_offenses(<<~RUBY)
        obj.public_send(:name)
      RUBY
    end

    it 'flags send' do
      expect_offense(<<~RUBY)
        obj.send(:x)
            ^^^^ `send` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_variable_get' do
      expect_offense(<<~RUBY)
        obj.instance_variable_get(:@x)
            ^^^^^^^^^^^^^^^^^^^^^ `instance_variable_get` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_variable_set' do
      expect_offense(<<~RUBY)
        obj.instance_variable_set(:@x, 1)
            ^^^^^^^^^^^^^^^^^^^^^ `instance_variable_set` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags instance_eval' do
      expect_offense(<<~RUBY)
        obj.instance_eval { 1 }
            ^^^^^^^^^^^^^ `instance_eval` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags const_get' do
      expect_offense(<<~RUBY)
        obj.const_get(:X)
            ^^^^^^^^^ `const_get` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags method' do
      expect_offense(<<~RUBY)
        obj.method(:x)
            ^^^^^^ `method` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end

    it 'flags __send__ exactly once as a bypass' do
      expect_offense(<<~RUBY)
        obj.__send__(:x)
            ^^^^^^^^ `__send__` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end

  describe 'mocking gem behaviour' do
    it 'flags expect_any_instance_of' do
      expect_offense(<<~RUBY)
        expect_any_instance_of(Foo)
        ^^^^^^^^^^^^^^^^^^^^^^ `expect_any_instance_of` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end

    it 'flags allow_any_instance_of' do
      expect_offense(<<~RUBY)
        allow_any_instance_of(Foo)
        ^^^^^^^^^^^^^^^^^^^^^ `allow_any_instance_of` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end

    it 'flags stub_const' do
      expect_offense(<<~RUBY)
        stub_const("X", 1)
        ^^^^^^^^^^ `stub_const` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end
  end

  describe 'default namespace' do
    let(:config) do
      RuboCop::Config.new('OdataDuty/PublicApiOnly' => {})
    end

    it 'defaults the Namespace to OdataDuty' do
      expect_offense(<<~RUBY)
        OdataDuty::Executor
        ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end
end
