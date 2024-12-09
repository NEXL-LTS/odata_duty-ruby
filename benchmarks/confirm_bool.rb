require 'bundler/setup'
require 'benchmark/ips'

def confirm_boolean_with_case(name, value)
  case value
  when true, false, nil
    value
  else
    raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
  end
end

require 'set'

VALID_BOOLEAN_VALUES = Set.new([true, false, nil]).freeze

def confirm_boolean_with_set(name, value)
  return value if VALID_BOOLEAN_VALUES.include?(value)

  raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
end

def confirm_boolean_direct(name, value)
  unless value == true || value == false || value.nil?
    raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
  end

  value
end

def confirm_boolean_simplified(name, value)
  unless value == true || value == false || value.nil?
    raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
  end

  value
end

data = 1000.times.map { [true, false, nil].sample }

Benchmark.ips do |x|
  x.report('confirm_boolean_with_case') do
    data.each { |value| confirm_boolean_with_case('bool', value) }
  end
  x.report('confirm_boolean_with_set') do
    data.each { |value| confirm_boolean_with_set('bool', value) }
  end
  x.report('confirm_boolean_direct') do
    data.each { |value| confirm_boolean_direct('bool', value) }
  end
  x.report('confirm_boolean_simplified') do
    data.each { |value| confirm_boolean_simplified('bool', value) }
  end

  x.compare!
end
