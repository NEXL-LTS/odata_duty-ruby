require 'spec_helper'

RSpec.describe OdataDuty::RequestError do
  it 'exposes an internal_server_error status by default' do
    expect(described_class.new.status).to eq(:internal_server_error)
  end

  it 'uses a default message when none is given' do
    expect(described_class.new.message).to eq('Request Error')
  end

  it 'preserves the message it is given' do
    expect(described_class.new('boom').message).to eq('boom')
  end

  it 'carries code and target' do
    error = described_class.new('boom', code: 'x', target: 'y')
    expect([error.code, error.target]).to eq(%w[x y])
  end

  it 'defaults code and target to nil' do
    error = described_class.new('boom')
    expect([error.code, error.target]).to eq([nil, nil])
  end
end

RSpec.describe OdataDuty::NoImplementationError do
  it 'reports a not_implemented status' do
    expect(described_class.new.status).to eq(:not_implemented)
  end
end

RSpec.describe OdataDuty::ClientError do
  it 'reports a bad_request status' do
    expect(described_class.new.status).to eq(:bad_request)
  end
end

RSpec.describe OdataDuty::ResourceNotFoundError do
  it 'reports a not_found status' do
    expect(described_class.new.status).to eq(:not_found)
  end
end
