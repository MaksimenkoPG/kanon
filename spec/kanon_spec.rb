# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Kanon do
  def with_fixtures
    previous = described_class.directory
    described_class.directory = File.expand_path('fixtures/kanon', __dir__)
    yield
  ensure
    described_class.directory = previous
  end

  around do |example|
    without_fixture_variables do
      with_fixtures do
        with_env('FIXTURE_TOKEN' => 'from-env', 'FIXTURE_EMPTY_ERB' => 'from-env') { example.run }
      end
    end
  end

  it 'reads a config having activated nothing but the standard library and the yaml backend' do
    script = <<~RUBY
      $LOAD_PATH.unshift 'lib'
      require 'kanon'
      Kanon.directory = 'spec/fixtures/kanon'
      Kanon.environment = 'test'
      ENV['FIXTURE_TOKEN'] = 'standalone'
      token = Kanon.read_config(:sectioned).token

      yaml_backend = Gem.loaded_specs['psych']
      backend_and_its_own = [yaml_backend.name, *yaml_backend.runtime_dependencies.map(&:name)]
      beyond_stdlib = Gem.loaded_specs.reject { |name, spec| backend_and_its_own.include?(name) || spec.default_gem? }

      print [token, beyond_stdlib.keys.sort.join(',')].join('|')
    RUBY

    expect(ruby_without_bundler(script)).to eq 'standalone|'
  end

  describe 'the psych compatibility branch' do
    it 'reads a config through the positional safe_load of psych 3.0' do
      script = <<~RUBY
        older = Gem::Specification.find_all_by_name('psych')
                                  .map(&:version)
                                  .select { |version| version < Gem::Version.new('3.1') }
                                  .max
        if older.nil?
          print 'no-old-psych'
        else
          gem 'psych', older.to_s
          require 'yaml'
          raise 'psych accepts keywords, the branch under test was not taken' if
            YAML.method(:safe_load).parameters.any? { |kind, name| kind == :key && name == :aliases }
          $LOAD_PATH.unshift 'lib'
          require 'kanon'
          Kanon.directory = 'spec/fixtures/kanon'
          Kanon.environment = 'test'
          ENV['FIXTURE_TOKEN'] = 'positional'
          print Kanon.read_config(:sectioned).token
        end
      RUBY

      output = ruby_without_bundler(script)

      skip 'no psych older than 3.1 installed' if output == 'no-old-psych'
      expect(output).to eq 'positional'
    end

    it 'hands the older psych its arguments positionally' do
      stub_const('Kanon::Document::KEYWORD_SAFE_LOAD', false)
      expect(YAML).to receive(:safe_load).
        with(kind_of(String), [Symbol], [], true).
        and_return(test: { fixture: { endpoint: 'from-positional' } })

      expect(described_class.read_config(:sectioned).endpoint).to eq 'from-positional'
    end
  end

  describe '.read_config' do
    it 'reads the section of the current environment and drops the single root key' do
      expect(described_class.read_config(:sectioned).endpoint).to eq 'https://fixture.example.com'
    end

    it 'prefers a variable over the default of a declaration' do
      with_env('FIXTURE_TIMEOUT' => '30') do
        expect(described_class.read_config(:sectioned).timeout).to eq 30
      end
    end

    it 'reads string keys the same as symbol keys' do
      with_env('STRINGY_TOKEN' => 'from-env', 'STRINGY_ENDPOINT' => 'overridden') do
        configuration = described_class.read_config(:stringy)

        expect(configuration.token).to eq 'from-env'
        expect(configuration.endpoint).to eq 'overridden'
        expect(configuration.api.timeout).to eq 5
      end
    end

    it 'keeps a filled scalar even when a variable with the derived name is set' do
      with_env('FIXTURE_ENDPOINT' => 'overridden') do
        expect(described_class.read_config(:sectioned).endpoint).to eq 'https://fixture.example.com'
      end
    end

    it 'names the missing variable of a required value' do
      with_env('FIXTURE_TOKEN' => nil) do
        expect { described_class.read_config(:sectioned) }.
          to raise_error Kanon::MissingValue, /FIXTURE_TOKEN/
      end
    end

    it 'leaves an optional value empty' do
      expect(described_class.read_config(:sectioned).legacy).to be_nil
    end

    it 'reads a list from a comma separated variable' do
      with_env('FIXTURE_RECIPIENTS' => 'a@fixture.example.com,b@fixture.example.com') do
        expect(described_class.read_config(:sectioned).recipients).
          to eq %w[a@fixture.example.com b@fixture.example.com]
      end
    end

    it 'returns a new object on every call' do
      expect(described_class.read_config(:sectioned)).not_to be described_class.read_config(:sectioned)
    end

    it 'takes the value an ERB tag produced' do
      with_env('FIXTURE_ERB_VALUE' => nil, 'FIXTURE_EMPTY_ERB' => 'from-env') do
        expect(described_class.read_config(:interpolated).from_erb).to eq 'erb-default'
      end
    end

    it 'reads the environment when an ERB tag produced nothing' do
      with_env('FIXTURE_ERB_VALUE' => nil, 'FIXTURE_EMPTY_ERB' => 'from-env') do
        expect(described_class.read_config(:interpolated).empty_erb).to eq 'from-env'
      end
    end

    it 'names the variable when an ERB tag produced nothing and the environment is empty too' do
      with_env('FIXTURE_ERB_VALUE' => nil, 'FIXTURE_EMPTY_ERB' => nil) do
        expect { described_class.read_config(:interpolated) }.
          to raise_error Kanon::MissingValue, /FIXTURE_EMPTY_ERB/
      end
    end

    it 'wraps a file whose root is an array into a node named after the file' do
      expect(described_class.read_config(:listing).listing.size).to eq 2
    end

    it 'names a value inside an array after the index it sits at' do
      with_env('FIXTURE_QUEUES_0_NAME' => 'primary', 'FIXTURE_BACKUP_QUEUE' => 'backup') do
        queues = described_class.read_config(:queued).queues

        expect(queues[0].name).to eq 'primary'
        expect(queues[0].weight).to eq 1
        expect(queues[1].name).to eq 'backup'
      end
    end

    it 'prefixes a value inside a root array with the file name' do
      with_env('INDEXED_0_ID' => '1', 'INDEXED_1_ID' => '2') do
        expect(described_class.read_config(:indexed).indexed[1].id).to eq '2'
      end
    end

    it 'freezes the strings inside an array it read' do
      expect(described_class.read_config(:sectioned).recipients.first).to be_frozen
    end

    it 'reads a hash of data that imitates a declaration as the default it carries' do
      expect(described_class.read_config(:imitation).to_h).to eq(rate: 0.2)
    end

    it 'freezes the arrays it read' do
      expect(described_class.read_config(:listing).listing).to be_frozen
    end

    it 'keeps the single root key of a file that holds one declaration' do
      expect(described_class.read_config(:lone).to_h).to eq(timeout: 5)
      expect(described_class.expected_variables(:lone)).to eq('TIMEOUT' => false)
    end

    it 'keeps the single root key that holds a list' do
      with_env('ENDPOINTS_0_URL' => 'https://fixture.example.com') do
        expect(described_class.read_config(:rooted).endpoints[0].url).to eq 'https://fixture.example.com'
      end
    end

    it 'keeps every root key of a file that has several' do
      configuration = described_class.read_config(:multiroot)

      expect(configuration.alpha.name).to eq 'first'
      expect(configuration.beta.name).to eq 'second'
    end

    it 'builds the variable name from the root key of a multi-root file' do
      with_env('BETA_NAME' => 'from-env') do
        expect(described_class.read_config(:multiroot).beta.name).to eq 'from-env'
      end
    end

    it 'returns an empty node for an empty environment section' do
      expect(described_class.read_config(:hollow).keys).to eq []
    end

    it 'reads the file again even when the cache already holds it' do
      cached = described_class.load_config(:sectioned)
      fresh = described_class.read_config(:sectioned)

      expect(fresh).not_to be cached
      expect(fresh).to eq cached
    end

    it 'refuses a derived name that starts with a digit' do
      expect { described_class.read_config(:'2fa') }.
        to raise_error Kanon::InvalidVariableName, /"2FA_0_CODE"/
    end

    it 'returns an empty node for a file with nothing in it' do
      expect(described_class.read_config(:empty).keys).to eq []
    end

    it 'reads the first document of a file and drops the rest' do
      expect(described_class.read_config(:twodocs).to_h).to eq(one: 1)
    end

    it 'names the file that does not exist' do
      expect { described_class.read_config(:no_such_config) }.
        to raise_error Kanon::FileMissing, /no_such_config\.yml/
    end

    it 'parses the file once' do
      allow(YAML).to receive(:safe_load).and_call_original

      described_class.read_config(:sectioned)

      expect(YAML).to have_received(:safe_load).once
    end

    it 'names the file that is not valid YAML' do
      expect { described_class.read_config(:malformed) }.
        to raise_error Kanon::InvalidSource, /malformed\.yml is not valid YAML/
    end

    it 'refuses a document that refers to itself through an alias' do
      expect { described_class.read_config(:recursive) }.
        to raise_error Kanon::InvalidSource, /refers to itself through an alias/
    end

    it 'refuses two keys that become one when they turn into symbols' do
      expect { described_class.read_config(:twinned) }.
        to raise_error Kanon::InvalidSource, /reads "fixture" and :fixture as one key/
    end

    it 'refuses a derived name no shell could set' do
      expect { described_class.read_config(:spaced) }.
        to raise_error Kanon::InvalidVariableName, /"FIXTURE_MY KEY"/
    end

    it 'refuses a name that is not a configuration file name' do
      [nil, [1, 2]].each do |name|
        expect { described_class.read_config(name) }.
          to raise_error Kanon::FileMissing, /is not a bare configuration file name/
      end

      expect { described_class.read_config(123) }.to raise_error Kanon::FileMissing, /123\.yml/
    end

    it 'refuses a file it cannot open' do
      Dir.mktmpdir do |directory|
        Dir.mkdir File.join(directory, 'blocked.yml')
        previous = described_class.directory
        described_class.directory = directory

        expect { described_class.read_config(:blocked) }.
          to raise_error Kanon::InvalidSource, /blocked\.yml cannot be opened/
      ensure
        described_class.directory = previous
      end
    end

    it 'names the file whose alias points at no anchor' do
      expect { described_class.read_config(:dangling) }.
        to raise_error Kanon::InvalidSource, /dangling\.yml cannot be built into a document/
    end

    it 'names the file whose ERB does not compile' do
      expect { described_class.read_config(:unclosed_erb) }.
        to raise_error Kanon::InvalidSource, /unclosed_erb\.yml failed while running ERB: SyntaxError/
    end

    it 'keeps the failure that broke a cast from travelling along as its cause' do
      with_env('FIXTURE_TIMEOUT' => 'S3CR3T') do
        expect { described_class.read_config(:sectioned) }.
          to raise_error(Kanon::InvalidValue) { |error| expect(error.cause).to be_nil }
      end
    end

    it 'keeps the failure that broke an ERB tag from travelling along as its cause' do
      with_env('FIXTURE_SECRET' => 'S3CR3T') do
        expect { described_class.read_config(:broken_erb) }.
          to raise_error(Kanon::InvalidSource) { |error| expect(error.cause).to be_nil }
      end
    end

    it 'names the file whose ERB fails' do
      expect { described_class.read_config(:broken_erb) }.
        to raise_error Kanon::InvalidSource, /broken_erb\.yml failed while running ERB: ArgumentError/
    end

    it 'reads a file whose structure is built by ERB' do
      expect(described_class.read_config(:structural).flag).to eq 'enabled'
    end

    it 'rejects a path in place of a configuration name' do
      expect { described_class.read_config(:'../secrets') }.
        to raise_error Kanon::FileMissing, /not a bare configuration file name/
    end

    it 'raises every failure under the common ancestor' do
      with_env('FIXTURE_TOKEN' => nil, 'FIXTURE_TIMEOUT' => 'not-a-number') do
        expect { described_class.read_config(:no_such_config) }.to raise_error Kanon::Error
        expect { described_class.read_config(:malformed) }.to raise_error Kanon::Error
        expect { described_class.read_config(:sectioned) }.to raise_error Kanon::Error
        expect { described_class[:sectioned][:nope] }.to raise_error Kanon::Error
      end
    end

    it 'keeps the value out of the error when ERB fails' do
      with_env('FIXTURE_SECRET' => 'super-secret-value') do
        expect { described_class.read_config(:broken_erb) }.
          to raise_error(Kanon::InvalidSource) { |error| expect(error.message).not_to include 'super-secret-value' }
      end
    end

    it 'rejects a YAML type outside the allowed list' do
      expect { described_class.read_config(:dated) }.
        to raise_error Kanon::InvalidSource, /dated\.yml holds a YAML type/
    end

    it 'reads the document whole when it carries no section for the environment' do
      expect(described_class.read_config(:multiroot).keys).to eq %i[alpha beta]
    end

    it 'refuses a sectioned file quietly read outside its sections' do
      previous = described_class.environment
      described_class.environment = 'production'

      expect { described_class.read_config(:sectioned) }.
        to raise_error Kanon::ConflictingVariable, /default\.fixture\.legacy and test\.fixture\.legacy/
    ensure
      described_class.environment = previous
    end
  end

  describe '.load_config' do
    it 'returns the same object on every call' do
      expect(described_class.load_config(:sectioned)).to be described_class.load_config(:sectioned)
    end

    it 'freezes the values it read' do
      expect { described_class.load_config(:sectioned).endpoint << 'tampered' }.to raise_error FrozenError
    end
  end

  describe '.[]' do
    it 'empties the cache when the environment changes' do
      cached = described_class.load_config(:sectioned)
      previous = described_class.environment
      described_class.environment = 'development'

      expect(described_class.load_config(:sectioned)).not_to be cached
    ensure
      described_class.environment = previous
    end

    it 'empties the cache when the directory changes' do
      cached = described_class.load_config(:sectioned)
      previous = described_class.directory
      described_class.directory = previous

      expect(described_class.load_config(:sectioned)).not_to be cached
    ensure
      described_class.directory = previous
    end

    it 'returns the cached node without reading the file again' do
      cached = described_class.load_config(:sectioned)

      expect(described_class[:sectioned]).to be cached
    end

    it 'hands out a file that carries no environment sections at all' do
      expect(described_class[:listing].listing.size).to eq 2
    end

    it 'loads a config that is not cached yet' do
      expect(described_class[:sectioned].endpoint).to eq 'https://fixture.example.com'
    end
  end

  describe '.expected_variables' do
    it 'names every variable the file reads and marks the mandatory ones' do
      expected = described_class.expected_variables(:sectioned)

      expect(expected['FIXTURE_TOKEN']).to be true
      expect(expected['FIXTURE_TIMEOUT']).to be false
      expect(expected['FIXTURE_LEGACY_NAME']).to be false
    end

    it 'reads no environment variable of its own' do
      with_env('FIXTURE_TOKEN' => 'already-set') do
        expect(described_class.expected_variables(:sectioned)['FIXTURE_TOKEN']).to be true
      end
    end

    it 'calls a value mandatory when its default casts to nothing' do
      expect(described_class.expected_variables(:emptylist)).to eq('FIXTURE_TAGS' => true)
    end

    it 'refuses a file whose two paths read one variable' do
      previous = described_class.environment
      described_class.environment = 'production'

      expect { described_class.expected_variables(:sectioned) }.
        to raise_error Kanon::ConflictingVariable, /FIXTURE_LEGACY_NAME/
    ensure
      described_class.environment = previous
    end

    it 'joins the index into the name of every value inside an array' do
      expect(described_class.expected_variables(:queued)).
        to eq('FIXTURE_QUEUES_0_NAME' => true, 'FIXTURE_QUEUES_0_WEIGHT' => false, 'FIXTURE_BACKUP_QUEUE' => true)
    end

    it 'names a value inside a root array after the file it came from' do
      expect(described_class.expected_variables(:indexed)).
        to eq('INDEXED_0_ID' => true, 'INDEXED_1_ID' => true)
    end

    it 'names a variable behind an ERB tag that produced nothing' do
      expect(described_class.expected_variables(:interpolated)).to eq('FIXTURE_EMPTY_ERB' => true)
    end
  end

  describe '.load_configs' do
    it 'returns a node for every name it was given' do
      configurations = described_class.load_configs(:sectioned, :interpolated)

      expect(configurations.keys).to eq %i[sectioned interpolated]
      expect(configurations[:sectioned].endpoint).to eq 'https://fixture.example.com'
    end

    it 'caches the nodes, not the hash' do
      first = described_class.load_configs(:sectioned)
      second = described_class.load_configs(:sectioned)

      expect(first).not_to be second
      expect(first[:sectioned]).to be second[:sectioned]
    end

    it 'fails at once when a required variable is missing' do
      with_env('FIXTURE_TOKEN' => nil) do
        expect { described_class.load_configs(:sectioned) }.
          to raise_error Kanon::MissingValue, /FIXTURE_TOKEN/
      end
    end
  end

  describe '.loaded_files' do
    it 'lists a file after it has been read' do
      described_class.load_config(:sectioned)

      expect(described_class.loaded_files).to include :sectioned
    end
  end

  describe '.directory' do
    it 'trims the directory it is handed' do
      previous = described_class.directory
      described_class.directory = "  #{previous}  "

      expect(described_class.directory).to eq previous
    ensure
      described_class.directory = previous
    end

    it 'refuses a directory with nothing in it' do
      expect { described_class.directory = '  ' }.
        to raise_error Kanon::EmptyDirectory, /cannot be empty/
    end

    it 'refuses no directory at all' do
      expect { described_class.directory = nil }.to raise_error Kanon::EmptyDirectory
    end
  end

  describe '.environment' do
    it 'refuses an environment name with nothing in it' do
      expect { described_class.environment = '  ' }.
        to raise_error Kanon::EmptyEnvironment, /cannot be empty/
    end

    it 'refuses no environment name at all' do
      expect { described_class.environment = nil }.to raise_error Kanon::EmptyEnvironment
    end

    it 'trims the environment name it is handed' do
      previous = described_class.environment
      described_class.environment = "  production\n"

      expect(described_class.environment).to eq 'production'
    ensure
      described_class.environment = previous
    end

    it 'prefers APP_ENV over the rest of the chain, and config over no directory' do
      script = <<~RUBY
        $LOAD_PATH.unshift 'lib'
        require 'kanon'
        print [Kanon.environment, Kanon.directory].join('|')
      RUBY

      with_env('APP_ENV' => 'app', 'RAILS_ENV' => 'rails', 'RACK_ENV' => 'rack') do
        expect(ruby_without_bundler(script)).to eq 'app|config'
      end
    end

    it 'skips an empty variable when it picks the environment' do
      script = <<~RUBY
        $LOAD_PATH.unshift 'lib'
        require 'kanon'
        print Kanon.environment
      RUBY

      with_env('APP_ENV' => '  ', 'RAILS_ENV' => 'staging', 'RACK_ENV' => nil) do
        expect(ruby_without_bundler(script)).to eq 'staging'
      end

      with_env('APP_ENV' => '', 'RAILS_ENV' => '', 'RACK_ENV' => '') do
        expect(ruby_without_bundler(script)).to eq 'development'
      end

      with_env('APP_ENV' => "  staging\n", 'RAILS_ENV' => nil, 'RACK_ENV' => nil) do
        expect(ruby_without_bundler(script)).to eq 'staging'
      end
    end
  end
end
