# frozen_string_literal: true

##
# Main entry point for the TweetX application.
# This module provides the core infrastructure for the tweet scheduler CLI.
#
module Tweetx
  require 'thor'
  require_relative 'tweetx/cli'
  require_relative 'tweetx/scheduler'
end
