# frozen_string_literal: true

RSpec.describe Kanon::Node do
  let(:node) { Kanon::Node.build(api: { url: 'https://example.com', token: 'secret' }) }

  it 'builds symbol keys out of the string keys it is given' do
    expect(described_class.build('api' => { 'url' => 'https://example.com' }).api.url).
      to eq 'https://example.com'
  end

  it 'answers respond_to? with false for a key it does not hold' do
    expect(node.respond_to?(:nope)).to be false
  end

  it 'refuses a key read with arguments' do
    expect { node.api('extra') }.to raise_error NoMethodError, /undefined method .api./
  end

  it 'hands out unfrozen arrays from to_h' do
    expect(described_class.build(hosts: %w[one two]).to_h[:hosts]).not_to be_frozen
  end

  it 'dumps its key names and nothing else to YAML' do
    expect(YAML.safe_load(YAML.dump(node.api))).to eq node.api.inspect
  end

  it 'reads a value as a method' do
    expect(node.api.url).to eq 'https://example.com'
  end

  it 'reads a value by key' do
    expect(node[:api][:url]).to eq 'https://example.com'
  end

  it 'reads a value by a string key' do
    expect(node['api']['url']).to eq 'https://example.com'
  end

  it 'reads a value by path' do
    expect(node.dig(:api, :url)).to eq 'https://example.com'
  end

  it 'digs through string keys' do
    expect(node.dig('api', 'url')).to eq 'https://example.com'
  end

  it 'answers key? for present and absent keys' do
    expect(node.key?('api')).to be true
    expect(node.key?(:nope)).to be false
  end

  it 'keeps a key that has no symbol form' do
    codes = Kanon::Node.build(codes: { 404 => 'not-found' })

    expect(codes.codes[404]).to eq 'not-found'
  end

  it 'lists available keys in the error for an unknown method' do
    expect { node.api.tokn }.to raise_error NoMethodError, /keys: url, token/
  end

  it 'names an unknown key' do
    expect { node[:nope] }.to raise_error Kanon::UnknownKey, /keys: api/
  end

  it 'refuses to dig into a scalar' do
    expect { node.dig(:api, :url, :tail) }.
      to raise_error Kanon::UnknownKey, 'no key tail inside a String'
  end

  it 'digs into an array by index' do
    expect(Kanon::Node.build(items: [{ id: 7 }]).dig(:items, 0, :id)).to eq 7
  end

  it 'reports an index outside the array as its own error' do
    listing = Kanon::Node.build(items: [{ id: 7 }])

    expect { listing.dig(:items, 5) }.to raise_error Kanon::UnknownKey, /no index 5 in an Array of 1/
    expect { listing.dig(:items, :id) }.to raise_error Kanon::UnknownKey, /no index id in an Array of 1/
  end

  it 'answers respond_to? for its keys' do
    expect(node.respond_to?(:api)).to be true
  end

  it 'hides values from inspect' do
    expect(node.api.inspect).to eq '#<Kanon::Node keys: url, token>'
  end

  it 'hides values from as_json and to_json' do
    expect(node.api.as_json).to eq '#<Kanon::Node keys: url, token>'
    expect(node.api.to_json).to eq '"#<Kanon::Node keys: url, token>"'
  end

  it 'refuses Marshal' do
    expect { Marshal.dump(node) }.to raise_error TypeError, /refuses serialization/
  end

  it 'hides values from YAML' do
    expect(YAML.dump(node)).not_to include 'secret'
  end

  it 'hides values from instance_variables' do
    expect(node.instance_variables).to eq []
  end

  it 'equals a node built from the same values' do
    twin = Kanon::Node.build(api: { url: 'https://example.com', token: 'secret' })

    expect(node).to eq twin
  end

  it 'differs from a node with other values' do
    other = Kanon::Node.build(api: { url: 'https://example.com', token: 'changed' })

    expect(node).not_to eq other
  end

  it 'does not equal a plain hash' do
    expect(node).not_to eq(api: { url: 'https://example.com', token: 'secret' })
  end

  it 'works as a hash key when equal' do
    twin = Kanon::Node.build(api: { url: 'https://example.com', token: 'secret' })

    expect({ node => 'kept' }[twin]).to eq 'kept'
    expect([node, twin].uniq.size).to eq 1
  end

  it 'returns a copy from to_h' do
    node.to_h[:api][:url] = 'tampered'

    expect(node.api.url).to eq 'https://example.com'
  end

  it 'unwraps nodes inside arrays from to_h' do
    listing = Kanon::Node.build(items: [{ id: 1 }])

    expect(listing.to_h).to eq(items: [{ id: 1 }])
  end

  it 'unwraps nodes inside nested arrays from to_h' do
    matrix = Kanon::Node.build(matrix: [[{ id: 1 }], [{ id: 2 }]])

    expect(matrix.to_h).to eq(matrix: [[{ id: 1 }], [{ id: 2 }]])
  end

  it 'freezes arrays' do
    expect { Kanon::Node.build(hosts: ['one']).hosts << 'two' }.to raise_error FrozenError
  end

  it 'rejects a key that clashes with an existing method' do
    expect { Kanon::Node.build(keys: 'whatever') }.
      to raise_error Kanon::ReservedKey, /keys clash with node methods/
  end

  it 'rejects a key that clashes with an inherited method' do
    expect { Kanon::Node.build(class: 'premium') }.
      to raise_error Kanon::ReservedKey, /class clash with node methods/
  end

  it 'allows a key named after a private Kernel method' do
    expect(Kanon::Node.build(format: 'pdf').format).to eq 'pdf'
  end
end
