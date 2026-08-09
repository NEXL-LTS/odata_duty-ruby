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

  %w[send instance_variable_get instance_variable_set instance_eval const_get
     method].each do |bypass_method|
    it "flags `#{bypass_method}` as a visibility bypass" do
      source = "set.#{bypass_method}(:converted_id, '1')"
      underline = (' ' * 'set.'.length) + ('^' * bypass_method.length)
      expect_offense(<<~RUBY)
        #{source}
        #{underline} `#{bypass_method}` bypasses method visibility. Specs must exercise the gem through its documented surface.
      RUBY
    end
  end

  it 'flags __send__ exactly once, as a bypass rather than a __-prefix hit' do
    expect_offense(<<~RUBY)
      set.__send__(:converted_id, '1')
          ^^^^^^^^ `__send__` bypasses method visibility. Specs must exercise the gem through its documented surface.
    RUBY
  end

  it 'flags a visibility bypass method with no explicit receiver' do
    expect_offense(<<~RUBY)
      send(:converted_id, '1')
      ^^^^ `send` bypasses method visibility. Specs must exercise the gem through its documented surface.
    RUBY
  end

  %w[expect_any_instance_of allow_any_instance_of stub_const].each do |mock_method|
    it "flags `#{mock_method}` as mocking gem behaviour" do
      source = "#{mock_method}(PeopleSet).to receive(:od_select)"
      underline = '^' * mock_method.length
      expect_offense(<<~RUBY)
        #{source}
        #{underline} `#{mock_method}` mocks gem behaviour. Specs must assert on the gem's output instead.
      RUBY
    end
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
