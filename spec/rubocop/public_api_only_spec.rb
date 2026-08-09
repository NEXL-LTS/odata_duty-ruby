require 'rubocop'
require 'rubocop/ast'
require_relative '../../rubocop/cop/odata_duty/public_api_only'
require_relative '../support/rubocop_cop_test_helper'

RSpec.describe RuboCop::Cop::OdataDuty::PublicApiOnly do
  include RubocopCopTestHelper

  let(:cop_config) do
    {
      'Namespace' => 'OdataDuty',
      'AllowedConstants' => [
        'OdataDuty::EntityType',
        'OdataDuty::ComplexType',
        'OdataDuty::EnumType',
        'OdataDuty::EntitySet',
        'OdataDuty::SetResolver',
        'OdataDuty::Schema',
        'OdataDuty::SchemaBuilder',
        'OdataDuty::EdmxSchema',
        'OdataDuty::OAS2',
        'OdataDuty::SearchExpression',
        'OdataDuty::SearchTerm',
        'OdataDuty::Generators::InstallGenerator',
        'OdataDuty::Generators::EntitySetGenerator'
      ],
      'AllowedConstantPatterns' => [
        '\AOdataDuty::\w*Error\z',
        '\AOdataDuty::Invalid\w+\z'
      ]
    }
  end

  context 'allowlisted constants' do
    it 'accepts EntitySet base class' do
      code = 'class PeopleSet < OdataDuty::EntitySet; end'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts EntityType base class' do
      code = 'class Person < OdataDuty::EntityType; end'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts Schema base class' do
      code = 'class MySchema < OdataDuty::Schema; end'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts error constants via Error pattern' do
      code = 'expect { subject }.to raise_error(OdataDuty::ResourceNotFoundError)'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts invalid error constants via Invalid pattern' do
      code = 'expect { subject }.to raise_error(OdataDuty::InvalidType)'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts SearchExpression' do
      code = 'def od_search(expression) = expression.terms'
      expect(inspect_source(code)).to be_empty
    end
  end

  context 'internal constants' do
    it 'flags an internal constant' do
      code = 'OdataDuty::Executor.execute(url: url, schema: schema)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include(
        '`OdataDuty::Executor` is not part of the public API'
      )
    end

    it 'flags a nested constant as top-level only' do
      code = 'OdataDuty::Schema::Metadata.new(schema)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`OdataDuty::Schema::Metadata`')
    end

    it 'does not double-report nested constants' do
      code = 'OdataDuty::Schema::Metadata.new'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(1)
    end

    it 'flags MapperBuilder as internal' do
      code = 'OdataDuty::MapperBuilder.new'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(1)
    end
  end

  context '__ prefixed methods' do
    it 'flags __metadata method call' do
      code = 'schema.__metadata.entity_sets'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`__metadata` is an internal method')
    end

    it 'flags __load method call' do
      code = 'obj.__load'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`__load` is an internal method (`__` prefix)')
    end

    it 'flags __ method on implicit receiver' do
      code = '__wrap'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
    end

    it 'flags __ method on self' do
      code = 'self.__metadata'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
    end

    it 'flags __send__ as internal method, once' do
      code = 'obj.__send__(:method)'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(1)
      expect(offenses.first.message).to include('`__send__`')
    end

    it 'flags __ method with safe navigation operator' do
      code = 'obj&.__metadata'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`__metadata` is an internal method')
    end
  end

  context 'visibility bypasses' do
    it 'accepts public_send' do
      code = 'record.public_send(property_name)'
      expect(inspect_source(code)).to be_empty
    end

    it 'flags send as bypass' do
      code = 'set.send(:converted_id, "1")'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`send` bypasses method visibility')
    end

    it 'flags instance_variable_get' do
      code = 'obj.instance_variable_get(:@ivar)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include(
        '`instance_variable_get` bypasses method visibility'
      )
    end

    it 'flags instance_variable_set' do
      code = 'obj.instance_variable_set(:@ivar, value)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include(
        '`instance_variable_set` bypasses method visibility'
      )
    end

    it 'flags instance_eval' do
      code = 'obj.instance_eval { @x }'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`instance_eval` bypasses method visibility')
    end

    it 'flags const_get' do
      code = "Object.const_get('OdataDuty::Executor')"
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`const_get` bypasses method visibility')
    end

    it 'flags method' do
      code = 'obj.method(:name)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`method` bypasses method visibility')
    end
  end

  context 'mocking methods' do
    it 'flags expect_any_instance_of' do
      code = 'expect_any_instance_of(SomeClass).to receive(:method)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`expect_any_instance_of` mocks gem behaviour')
    end

    it 'reports mocking message' do
      code = 'expect_any_instance_of(SomeClass).to receive(:od_select)'
      offenses = inspect_source(code)
      expect(offenses.first.message).to include('assert on the gem\'s output instead')
    end

    it 'flags allow_any_instance_of' do
      code = 'allow_any_instance_of(SomeClass).to receive(:method)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`allow_any_instance_of` mocks gem behaviour')
    end

    it 'flags stub_const' do
      code = 'stub_const("SomeNamespace::Constant", double)'
      offenses = inspect_source(code)
      expect(offenses).to have_attributes(size: 1)
      expect(offenses.first.message).to include('`stub_const` mocks gem behaviour')
    end
  end

  context 'namespace configuration' do
    it 'uses default namespace when Namespace is not set' do
      config_no_ns = {
        'AllowedConstants' => ['OdataDuty::EntitySet'],
        'AllowedConstantPatterns' => ['\AOdataDuty::\w*Error\z']
      }

      code = 'OdataDuty::EntitySet'
      offenses = inspect_source(code, config_no_ns)
      expect(offenses).to be_empty
    end

    it 'constants matching patterns are allowed' do
      code = 'OdataDuty::SomeError'
      expect(inspect_source(code)).to be_empty
    end

    it 'constants not matching any pattern are flagged' do
      code = 'OdataDuty::SomeClass'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(1)
    end

    it 'constants in different namespace are not flagged' do
      code = 'SomeOther::Class'
      expect(inspect_source(code)).to be_empty
    end
  end

  context 'spec file detection' do
    it 'contains internal constant names as strings for testing' do
      # This is a heredoc test to verify the cop does not flag
      # internal names when they appear as strings
      code = <<~RUBY
        it 'works' do
          # This string contains "OdataDuty::Executor" but should not be flagged
          expect(msg).to include("OdataDuty::Executor")
        end
      RUBY
      expect(inspect_source(code)).to be_empty
    end
  end

  context 'constant parents' do
    it 'handles constant in method argument' do
      code = 'schema.execute(OdataDuty::Executor)'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(1)
      expect(offenses.first.message).to include('`OdataDuty::Executor`')
    end
  end

  context 'namespace constant' do
    it 'accepts bare namespace constant' do
      code = 'RSpec.describe(OdataDuty) { }'
      expect(inspect_source(code)).to be_empty
    end

    it 'accepts bare namespace in describe' do
      code = 'describe OdataDuty do; end'
      expect(inspect_source(code)).to be_empty
    end
  end

  context 'integration' do
    it 'multiple violations on same line' do
      code = 'OdataDuty::Executor.new.send(:method)'
      offenses = inspect_source(code)
      expect(offenses.size).to eq(2)
    end
  end
end
