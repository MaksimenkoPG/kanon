# frozen_string_literal: true

RSpec.describe Kanon::EnvDeclarations do
  let(:resolver) { described_class.new(:demo, [:demo]) }

  around { |example| without_fixture_variables { example.run } }

  it 'reports the class and the length of a value it could not cast' do
    with_env('DEMO_PORT' => 'not-a-number') do
      expect { resolver.resolve(port: { env: 'DEMO_PORT', type: 'integer' }) }.
        to raise_error Kanon::InvalidValue, /got String of 12 characters/
    end
  end

  it 'reads every word of the boolean vocabulary in any case' do
    { '1' => true, 'ON' => true, 'Yes' => true, 'TRUE' => true,
      '0' => false, 'Off' => false, 'no' => false, 'FALSE' => false }.each do |raw, expected|
      with_env('DEMO_FLAG' => raw) do
        expect(resolver.resolve(flag: { env: 'DEMO_FLAG', type: 'boolean' })).to eq(flag: expected)
      end
    end
  end

  it 'keeps a hash as data when its only key is a misspelt declaration key' do
    expect(resolver.resolve(timeout: { dfault: 5 })).to eq(timeout: { dfault: 5 })
  end

  it 'refuses a declaration whose type is written and left empty' do
    expect { resolver.resolve(timeout: { type: nil, default: 5 }) }.
      to raise_error Kanon::InvalidValue, /declares unknown type/
  end

  it 'refuses a written-out name no shell could set' do
    expect { resolver.resolve(api: { token: { env: 'MY TOKEN' } }) }.
      to raise_error Kanon::InvalidVariableName, /"MY TOKEN"/
  end

  it 'derives the variable name from the path' do
    with_env('DEMO_API_TOKEN' => 'from-env') do
      expect(resolver.resolve(api: { token: nil })).to eq(api: { token: 'from-env' })
    end
  end

  it 'keeps the default when the variable is absent' do
    with_env('DEMO_API_URL' => nil) do
      expect(resolver.resolve(api: { url: { default: 'https://example.com' } })).
        to eq(api: { url: 'https://example.com' })
    end
  end

  it 'prefers the variable over the default' do
    with_env('DEMO_API_URL' => 'https://other.example.com') do
      expect(resolver.resolve(api: { url: { default: 'https://example.com' } })[:api][:url]).
        to eq 'https://other.example.com'
    end
  end

  it 'keeps a filled scalar out of the environment lookup' do
    with_env('DEMO_API_URL' => 'https://other.example.com') do
      expect(resolver.resolve(api: { url: 'https://example.com' })).to eq(api: { url: 'https://example.com' })
    end
  end

  it 'takes the name from an explicit declaration' do
    with_env('LEGACY_TOKEN' => 'from-env') do
      expect(resolver.resolve(token: { env: 'LEGACY_TOKEN' })).to eq(token: 'from-env')
    end
  end

  it 'treats an empty variable as absent' do
    with_env('DEMO_SUBDOMAIN' => '') do
      expect { resolver.resolve(subdomain: nil) }.
        to raise_error Kanon::MissingValue, /DEMO_SUBDOMAIN/
    end
  end

  it 'lists every missing variable at once' do
    with_env('DEMO_ONE' => nil, 'DEMO_TWO' => nil) do
      expect { resolver.resolve(one: nil, two: nil) }.
        to raise_error Kanon::MissingValue, /DEMO_ONE, DEMO_TWO/
    end
  end

  it 'takes the type from the default' do
    with_env('DEMO_POOL' => '25') do
      expect(resolver.resolve(pool: { default: 5 })).to eq(pool: 25)
    end
  end

  it 'takes the type from the declaration' do
    with_env('DEMO_DUALSTACK' => 'yes') do
      expect(resolver.resolve(dualstack: { env: 'DEMO_DUALSTACK', type: 'boolean' })).to eq(dualstack: true)
    end
  end

  it 'applies the declared type to the default' do
    with_env('DEMO_POOL' => nil) do
      expect(resolver.resolve(pool: { env: 'DEMO_POOL', type: 'integer', default: '42' })).to eq(pool: 42)
    end
  end

  it 'splits a list variable by commas' do
    with_env('DEMO_EMAILS' => 'a@x.com, b@x.com ,c@x.com') do
      expect(resolver.resolve(emails: { env: 'DEMO_EMAILS', type: 'list' })).to eq(emails: %w[a@x.com b@x.com c@x.com])
    end
  end

  it 'keeps the default array when the list variable is absent' do
    with_env('DEMO_EMAILS' => nil) do
      expect(resolver.resolve(emails: { env: 'DEMO_EMAILS', type: 'list', default: ['a@x.com'] })).
        to eq(emails: ['a@x.com'])
    end
  end

  it 'takes the list type from an array default' do
    with_env('DEMO_EMAILS' => 'a@x.com,b@x.com') do
      expect(resolver.resolve(emails: { default: ['z@x.com'] })).to eq(emails: %w[a@x.com b@x.com])
    end
  end

  it 'takes the boolean type from a false default' do
    with_env('DEMO_DUALSTACK' => 'true') do
      expect(resolver.resolve(dualstack: { default: false })).to eq(dualstack: true)
    end
  end

  it 'takes the float type from a float default' do
    with_env('DEMO_RATE' => '2.5') do
      expect(resolver.resolve(rate: { default: 1.0 })).to eq(rate: 2.5)
    end
  end

  it 'reads a leading zero as a decimal number' do
    with_env('DEMO_PORT' => '010') do
      expect(resolver.resolve(port: { env: 'DEMO_PORT', type: 'integer' })).to eq(port: 10)
    end
  end

  it 'treats a list of empty items as a missing value' do
    with_env('DEMO_EMAILS' => ' , ') do
      expect { resolver.resolve(emails: { env: 'DEMO_EMAILS', type: 'list' }) }.
        to raise_error Kanon::MissingValue, /DEMO_EMAILS/
    end
  end

  it 'rejects an unknown type before the variable is set' do
    with_env('DEMO_MODE' => nil) do
      expect { resolver.resolve(mode: { env: 'DEMO_MODE', type: 'strnig', optional: true }) }.
        to raise_error Kanon::InvalidValue, /unknown type/
    end
  end

  it 'takes optional only from a literal true' do
    with_env('DEMO_API_TOKEN' => nil) do
      expect { resolver.resolve(api: { token: { optional: 'false' } }) }.
        to raise_error Kanon::MissingValue, /DEMO_API_TOKEN/
    end
  end

  it 'casts the default to the declared string type' do
    with_env('DEMO_PORT' => nil) do
      expect(resolver.resolve(port: { env: 'DEMO_PORT', type: 'string', default: 8080 })).to eq(port: '8080')
    end
  end

  it 'keeps the value out of the error when the type does not match' do
    with_env('DEMO_POOL' => 'super-secret-value') do
      expect { resolver.resolve(pool: { default: 5 }) }.
        to raise_error(Kanon::InvalidValue) { |error| expect(error.message).not_to include 'super-secret-value' }
    end
  end

  it 'casts a float by the declared type' do
    with_env('DEMO_RATE' => '2.5') do
      expect(resolver.resolve(rate: { env: 'DEMO_RATE', type: 'float' })).to eq(rate: 2.5)
    end
  end

  it 'reads a false value of a boolean' do
    with_env('DEMO_DUALSTACK' => 'off') do
      expect(resolver.resolve(dualstack: { env: 'DEMO_DUALSTACK', type: 'boolean' })).to eq(dualstack: false)
    end
  end

  it 'rejects a value outside the boolean dictionary' do
    with_env('DEMO_DUALSTACK' => 'banana') do
      expect { resolver.resolve(dualstack: { env: 'DEMO_DUALSTACK', type: 'boolean' }) }.
        to raise_error Kanon::InvalidValue, /must be one of/
    end
  end

  it 'rejects a declaration with an unknown type' do
    with_env('DEMO_MODE' => 'strict') do
      expect { resolver.resolve(mode: { env: 'DEMO_MODE', type: 'money' }) }.
        to raise_error Kanon::InvalidValue, /unknown type/
    end
  end

  it 'rejects a value of the wrong type' do
    with_env('DEMO_POOL' => 'many') do
      expect { resolver.resolve(pool: { default: 5 }) }.
        to raise_error Kanon::InvalidValue, /DEMO_POOL must be an integer/
    end
  end

  it 'allows a missing value when it is declared optional' do
    with_env('DEMO_API_TOKEN' => nil) do
      expect(resolver.resolve(api: { token: { optional: true } })).to eq(api: { token: nil })
    end
  end

  it 'still reads an optional value when the variable is set' do
    with_env('DEMO_API_TOKEN' => 'from-env') do
      expect(resolver.resolve(api: { token: { optional: true } })).to eq(api: { token: 'from-env' })
    end
  end

  it 'requires every value that is not declared optional' do
    with_env('DEMO_API_TOKEN' => nil) do
      expect { resolver.resolve(api: { token: nil }) }.
        to raise_error Kanon::MissingValue, /DEMO_API_TOKEN/
    end
  end

  it 'derives the name for a declaration without one' do
    with_env('DEMO_POOL' => '25') do
      expect(resolver.resolve(pool: { type: 'integer' })).to eq(pool: 25)
    end
  end

  it 'rejects a typo in the declaration itself' do
    expect { resolver.resolve(token: { env: 'DEMO_TOKEN', dfault: 'x' }) }.
      to raise_error Kanon::InvalidDeclaration, /unsupported keys \[:dfault\]/
  end

  it 'keeps filled array elements as they are' do
    expect(resolver.resolve(items: [{ id: 1, key: 'literal' }])).to eq(items: [{ id: 1, key: 'literal' }])
  end

  it 'resolves values inside an array by their index' do
    with_env('DEMO_ITEMS_0_KEY' => 'from-env') do
      expect(resolver.resolve(items: [{ id: 1, key: nil }])).to eq(items: [{ id: 1, key: 'from-env' }])
    end
  end

  it 'requires a declaration placed inside an array' do
    with_env('INSIDE_ARRAY' => nil) do
      expect { resolver.resolve(items: [{ env: 'INSIDE_ARRAY' }]) }.
        to raise_error Kanon::MissingValue, /INSIDE_ARRAY/
    end
  end

  it 'treats an empty value as missing whatever produced it' do
    with_env('DEMO_API_TOKEN' => nil) do
      expect { resolver.resolve(api: { token: nil }) }.
        to raise_error Kanon::MissingValue, /DEMO_API_TOKEN/
    end
  end

  it 'builds the name from the root key of the file' do
    expect(resolver.variable_name(%i[api token])).to eq 'DEMO_API_TOKEN'
  end

  it 'rejects two paths that derive one variable name' do
    with_env('DEMO_A_B_C' => 'from-env') do
      expect { resolver.resolve(a: { b_c: nil }, a_b: { c: nil }) }.
        to raise_error Kanon::ConflictingVariable, /DEMO_A_B_C for both a\.b_c and a_b\.c/
    end
  end
end
