# frozen_string_literal: true

##
# Gemfile for TweetX - A Developer-First Tweet Automation Toolkit.
# Manages Ruby dependencies for the TweetX application.
#

source 'https://rubygems.org'

ruby '3.2.2'

# CLI framework for command-line interface
gem 'thor'

# Environment variables and API credentials
gem 'dotenv'
gem 'x' # Official Twitter/X API gem

# Standard library extensions and utilities
gem 'csv'    # CSV file handling
gem 'debug'  # Debugging support
gem 'time'   # Time utilities
gem 'tzinfo' # Timezone information

# Tests and linting. Not needed to run the CLI, so set
# BUNDLE_WITHOUT=development:test wherever you only need `bin/tweetx`.
group :development, :test do
  gem 'rspec'                         # test framework
  gem 'rubocop', require: false       # style and lint checks
  gem 'rubocop-rspec', require: false # RSpec-specific cops
end
