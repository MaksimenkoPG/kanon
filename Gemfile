# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

psych_version = ENV.fetch('PSYCH_VERSION', nil)
gem 'psych', psych_version if psych_version

group :development do
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.25'
end
