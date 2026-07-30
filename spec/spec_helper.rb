# frozen_string_literal: true

# This runs before any application file is loaded, which matters because
# scheduler.rb calls dotenv/load, and dotenv does NOT override variables that
# are already set. Assigning placeholders here keeps a developer's real .env
# from handing live X API credentials to the suite.
ENV['X_API_KEY'] ||= 'test-api-key'
ENV['X_API_KEY_SECRET'] ||= 'test-api-key-secret'
ENV['X_ACCESS_TOKEN'] ||= 'test-access-token'
ENV['X_ACCESS_TOKEN_SECRET'] ||= 'test-access-token-secret'

require 'csv'
require 'fileutils'
require 'tmpdir'

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include CsvFixtures

  # No spec may ever construct a real X::Client. Even with credentials present
  # in the environment, every Scheduler built during the suite talks to a fake.
  config.before do
    allow(X::Client).to receive(:new).and_return(FakeXClient.new) if defined?(X::Client)
  end
end
