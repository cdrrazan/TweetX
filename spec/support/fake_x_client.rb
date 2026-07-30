# frozen_string_literal: true

# Stand-in for X::Client.
#
# Records what would have been posted and returns the same shape the real client
# returns for POST /tweets, so Scheduler's response handling is exercised without
# any network access. Set #next_response or #raise_on_post to drive the failure
# branches.
class FakeXClient
  attr_reader :posts
  attr_accessor :next_response, :raise_on_post

  DEFAULT_TWEET_ID = '1234567890'

  def initialize
    @posts = []
    @next_response = { 'data' => { 'id' => DEFAULT_TWEET_ID } }
    @raise_on_post = nil
  end

  # Mirrors X::Client#post(path, body).
  #
  # @param path [String] API path, e.g. 'tweets'
  # @param body [String] JSON request body
  # @return [Hash] canned API response
  def post(path, body = nil)
    @posts << { path: path, body: body }
    raise @raise_on_post if @raise_on_post

    @next_response
  end

  # Text of the most recent post, decoded from the JSON body.
  # @return [String, nil]
  def last_posted_text
    return nil if @posts.empty?

    JSON.parse(@posts.last[:body])['text']
  end
end
