require 'spec_helper'
require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../rubocop/cop/odata_duty/public_api_only'

RSpec.describe RuboCop::Cop::OdataDuty::PublicApiOnly, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) do
    {
      'Namespace' => 'OdataDuty',
      'AllowedConstants' => %w[
        OdataDuty::EntityType
        OdataDuty::Schema
      ],
      'AllowedConstantPatterns' => [
        '\AOdataDuty::\w*Error\z',
        '\AOdataDuty::Invalid\w+\z'
      ]
    }
  end

  it 'accepts an allowlisted constant' do
    expect_no_offenses(<<~RUBY)
      class PeopleSet < OdataDuty::EntityType
      end
    RUBY
  end

  it 'accepts a constant matched by the Error suffix pattern' do
    expect_no_offenses(<<~RUBY)
      expect { subject }.to raise_error(OdataDuty::ResourceNotFoundError)
    RUBY
  end

  it 'accepts a constant matched by the Invalid prefix pattern' do
    expect_no_offenses(<<~RUBY)
      expect { subject }.to raise_error(OdataDuty::InvalidType)
    RUBY
  end

  it 'flags an internal constant not on the allowlist' do
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

  it 'flags an internal constant passed as a bare argument (send-node parent)' do
    expect_offense(<<~RUBY)
      foo(OdataDuty::Executor)
          ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'flags a bare top-level constant reference with no parent node at all' do
    expect_offense(<<~RUBY)
      OdataDuty::Executor
      ^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor` is not part of the public API. Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'flags a doubly-nested internal constant exactly once, not once per level' do
    expect_offense(<<~RUBY)
      OdataDuty::Executor::Internal.new
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `OdataDuty::Executor::Internal` is not part of the public API. Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'flags a __-prefixed method call on an explicit receiver' do
    expect_offense(<<~RUBY)
      schema.__metadata.entity_sets
             ^^^^^^^^^^ `__metadata` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'flags a __-prefixed method call via safe navigation, regardless of receiver' do
    expect_offense(<<~RUBY)
      object&.__wrap
              ^^^^^^ `__wrap` is an internal method (`__` prefix). Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'accepts a __-prefixed call with no receiver, e.g. Kernel#__dir__' do
    expect_no_offenses(<<~'RUBY')
      File.read("#{__dir__}/fixture.json")
    RUBY
  end

  it 'accepts a normal, non-__-prefixed method call' do
    expect_no_offenses(<<~RUBY)
      schema.metadata
    RUBY
  end

  it 'accepts public_send, since it does not start with __' do
    expect_no_offenses(<<~RUBY)
      record.public_send(:foo)
    RUBY
  end

  context 'when the config has no Namespace key' do
    let(:cop_config) do
      {
        'AllowedConstants' => ['OdataDuty::EntityType'],
        'AllowedConstantPatterns' => []
      }
    end

    it 'defaults the namespace prefix to OdataDuty' do
      expect_no_offenses(<<~RUBY)
        class PeopleSet < OdataDuty::EntityType
        end
      RUBY
    end
  end
end
