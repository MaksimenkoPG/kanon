# frozen_string_literal: true

module KanonHelpers
  REPOSITORY_ROOT = File.expand_path('../..', __dir__).freeze
  FIXTURE_VARIABLE = /\A(ALPHA|BETA|DEMO|ENDPOINTS|FIXTURE|INDEXED|PRIMARY|STRINGY|TIMEOUT)/.freeze

  def without_fixture_variables
    saved = ENV.select { |name, _| name.match?(FIXTURE_VARIABLE) }
    saved.each_key { |name| ENV.delete(name) }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end

  def with_env(values)
    saved = values.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  def ruby_without_bundler(script)
    without_bundler = { 'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLER_VERSION' => nil }

    Dir.chdir(REPOSITORY_ROOT) do
      IO.popen(without_bundler, ['ruby', '-e', script], err: %i[child out], &:read)
    end
  end
end
