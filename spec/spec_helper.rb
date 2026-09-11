# frozen_string_literal: true

require 'kanon'

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |file| require file }

Kanon.environment = 'test'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include KanonHelpers

  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
  end
end
