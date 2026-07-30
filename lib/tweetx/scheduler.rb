# frozen_string_literal: true

require 'csv'
require 'dotenv/load'
require 'securerandom'
require 'time'
require 'tzinfo'
require 'x'
require 'debug'

##
# Core scheduler class for TweetX.
# Handles tweet posting, selection, and management based on time-based categories.
#
class Scheduler
  ROOT_DIR = File.expand_path('../../', __dir__)
  DATA_DIR = File.join(ROOT_DIR, 'data')

  TWEET_COLLECTION_FILE = File.join(DATA_DIR, 'tweet_collection.csv')
  TWEET_PUBLISHED_FILE = File.join(DATA_DIR, 'tweet_published.csv')

  ##
  # Initialize the scheduler with X/Twitter API client.
  # Loads credentials from environment variables via dotenv.
  #
  def initialize
    @client = X::Client.new(
      api_key: ENV.fetch('X_API_KEY', nil),
      api_key_secret: ENV.fetch('X_API_KEY_SECRET', nil),
      access_token: ENV.fetch('X_ACCESS_TOKEN', nil),
      access_token_secret: ENV.fetch('X_ACCESS_TOKEN_SECRET', nil)
    )
  end

  ##
  # The four OAuth 1.0a values without which no post can succeed.
  #
  REQUIRED_CREDENTIALS = %w[
    X_API_KEY
    X_API_KEY_SECRET
    X_ACCESS_TOKEN
    X_ACCESS_TOKEN_SECRET
  ].freeze

  ##
  # Main runner method that posts a tweet.
  # Selects an appropriate tweet based on current time and posts it to X/Twitter.
  #
  # The return value is what the CLI turns into an exit status, so it
  # distinguishes "nothing to do" from "tried and failed". Having nothing to
  # post is normal — it happens every night between 00:00 and 05:00 — and must
  # not fail a scheduled job. A rejected API call must.
  #
  # @param dry_run [Boolean] If true, only previews the tweet without posting
  # @return [Boolean] false only if posting was attempted and failed
  #
  def run(dry_run: false)
    selected = select_tweet

    if selected.nil?
      puts '🚫 No text available to tweet.'
      return true
    end

    category, tweet = selected

    formatted_tweet = format_tweet(tweet)
    unless valid_tweet?(formatted_tweet)
      puts "⚠️ Skipping invalid tweet (empty or >280 characters): #{formatted_tweet.inspect}"
      return true
    end

    if dry_run
      puts "🤖 [DRY RUN] Would tweet:\n#{formatted_tweet}"
      return true
    end

    post_tweet(formatted_tweet, category, tweet)
  end

  ##
  # Posts to X and records the result.
  #
  # @param formatted_tweet [String] The text actually sent
  # @param category [String] Category of the selected tweet
  # @param tweet [String] The raw body, as stored in the CSV
  # @return [Boolean] True if the API accepted the tweet
  #
  def post_tweet(formatted_tweet, category, tweet)
    # Check before calling out, because X answers a request signed with empty
    # credentials and one signed with rejected credentials identically: 401
    # "Unauthorized". Without this you cannot tell a credential that never
    # arrived from a token that has been revoked.
    missing = missing_credentials
    unless missing.empty?
      puts "❌ Not posting: no value for #{missing.join(', ')}."
      puts '   In GitHub Actions these come from repository secrets; locally from .env.'
      return false
    end

    response = @client.post('tweets', { text: formatted_tweet }.to_json)
    obj_id = response.dig(:data, :id) || response.dig('data', 'id')

    unless obj_id
      # A 2xx with no id should not be possible, but silently treating it as
      # success would drop the tweet without recording it.
      puts '❌ Failed to tweet: the API accepted the request but returned no tweet id.'
      puts "   Response: #{response.inspect}"
      return false
    end

    puts "✅ Tweeted: #{tweet}"
    send_to_published(obj_id, category, tweet)
    true
  rescue X::HTTPError => e
    puts "❌ Failed to tweet: HTTP #{e.code} — #{e.message}"
    puts "   Response body: #{e.response.body}" if e.response.respond_to?(:body)
    puts credential_hint(e.code)
    false
  rescue StandardError => e
    puts "❌ Failed to tweet: #{e.class} — #{e.message}"
    false
  end

  ##
  # @return [Array<String>] Names of credentials that are unset or blank
  #
  def missing_credentials
    REQUIRED_CREDENTIALS.select { |name| ENV.fetch(name, nil).to_s.strip.empty? }
  end

  ##
  # Turns the two auth failures that actually happen into something actionable.
  # They are easy to confuse and the fixes are completely different.
  #
  # @param code [String, Integer] HTTP status returned by X
  # @return [String] Guidance to print, or an empty string
  #
  def credential_hint(code)
    case code.to_s
    when '401'
      '   401 means X rejected the credentials themselves. The four OAuth 1.0a ' \
      "values must come from one app and be current:\n   " \
      'X_API_KEY / X_API_KEY_SECRET (app) and X_ACCESS_TOKEN / ' \
      "X_ACCESS_TOKEN_SECRET (user).\n   " \
      'Regenerating any of them, or changing the app permissions, ' \
      'invalidates the old access token — regenerate the token pair after ' \
      'any permission change.'
    when '403'
      '   403 means the credentials are valid but not allowed to post. Check ' \
      'that the app has Read and Write permissions, that the access token ' \
      'was regenerated after that was set, and that the app belongs to a Project.'
    else
      ''
    end
  end

  ##
  # Validates if a tweet text is valid (not empty and within 280 character limit).
  #
  # @param text [String] The tweet text to validate
  # @return [Boolean] True if valid, false otherwise
  #
  def valid_tweet?(text)
    return false if text.nil? || text.strip.empty? || text.length > 280

    true
  end

  ##
  # Selects a tweet based on current time and category.
  # Returns a random unpublished tweet from the appropriate time-based category.
  #
  # @return [Array, nil] Array containing [category, tweet_text] or nil if no tweet available
  #
  def select_tweet
    return nil unless File.exist?(TWEET_COLLECTION_FILE)

    all_tweets = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    published = published_tweets
    category = category_for_current_hour
    # Report the hour the category was actually derived from. This used to print
    # Time.now.hour, which on a UTC CI runner showed 15 next to a category
    # chosen for 21:00 Kathmandu — the two never matched and it read as a bug.
    puts "🕒 Current time: #{my_timezone.strftime('%H:%M %Z')} → Category: #{category || 'unspecified'}"

    tweets_by_category = category ? all_tweets.select { |row| row['category'] == category } : []
    unpublished_tweets = tweets_by_category.reject { |row| published.include?(row['tweet']) }

    if unpublished_tweets.empty?
      puts "⚠️ No unpublished tweets available in category '#{category}'. Skipping tweet."
      return nil
    end

    unpublished = unpublished_tweets.sample
    [unpublished['category'], unpublished['tweet']]
  end

  ##
  # Retrieves all previously published tweets from the published CSV file.
  #
  # @return [Array<String>] Array of tweet text strings
  #
  def published_tweets
    return [] unless File.exist?(TWEET_PUBLISHED_FILE)

    CSV.read(TWEET_PUBLISHED_FILE, headers: true).map { |row| row['tweet'] }
  end

  ##
  # Saves a published tweet to the published CSV file.
  #
  # @param id [String] The tweet ID from X/Twitter
  # @param category [String] The category of the tweet
  # @param text [String] The tweet text content
  # @return [void]
  #
  def send_to_published(id, category, text)
    CSV.open(TWEET_PUBLISHED_FILE, 'a+') do |csv|
      # `csv` is a CSV handle opened for append, not an Array. RuboCop suggests
      # none?, but counting the rows already in the file is what decides whether
      # a header is still needed, so the intent is clearer spelled out.
      csv << %w[id category tweet timestamp] if csv.count.zero? # rubocop:disable Style/CollectionQuerying
      timestamp = Time.now.utc.iso8601

      csv << [id, category, text, timestamp]
    end
  end

  ##
  # Previews which tweet would be selected and posted based on current time.
  # Shows the tweet content without actually posting it.
  #
  # @return [void]
  #
  def preview
    tweet_info = select_tweet

    if tweet_info.nil?
      puts '🚫 No tweet available to preview.'
    else
      puts "🔍 Previewing tweet for category: #{tweet_info[0]}"
      puts '-' * 60
      puts format_tweet(tweet_info[1])
      puts '-' * 60
      puts "🕒 Time slot: #{my_timezone.strftime('%I:%M %p %Z')}"
    end
  end

  ##
  # Determines the appropriate category based on the current hour.
  #
  # @return [String, nil] The category name or nil if no matching time slot
  #
  def category_for_current_hour
    hour = my_timezone.hour

    case hour
    when 5..8 then 'Motivation'
    when 9..12 then 'Devtip'
    when 13..16 then 'Branding'
    when 17..20 then 'Builtwith'
    when 21..23 then 'Ebook'
    end
  end

  ##
  # Lists all unpublished tweets across all categories.
  # Shows available tweets that have not been posted yet.
  #
  # @return [void]
  #
  def list_tweets
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    published = published_tweets
    unpublished = all.reject { |row| published.include?(row['tweet']) }

    if unpublished.empty?
      puts '📭 No unpublished tweets found.'
    else
      puts '📋 Unpublished tweets:'
      unpublished.each_with_index do |row, i|
        puts "#{i + 1}. [#{row['category']}] #{row['tweet']}"
      end
    end
  end

  ##
  # Lists all previously published tweets from the archive.
  #
  # @return [void]
  #
  def list_published
    if File.exist?(TWEET_PUBLISHED_FILE)
      published = CSV.read(TWEET_PUBLISHED_FILE, headers: true)
      puts '🗃 Published tweets:'
      published.each_with_index do |row, i|
        puts "#{i + 1}. #{row['tweet']}"
      end
    else
      puts '📭 No published tweets yet.'
    end
  end

  ##
  # Adds a new tweet to the collection under the specified category.
  #
  # @param text [String] The tweet text content
  # @param category [String] The category to add the tweet to
  # @return [void]
  #
  def add_tweet(text, category)
    CSV.open(TWEET_COLLECTION_FILE, 'a+') do |csv|
      # See the note in send_to_published: `csv` is an append handle, and the
      # row count is what decides whether a header still has to be written.
      csv << %w[id category tweet] if csv.count.zero? # rubocop:disable Style/CollectionQuerying
      id = SecureRandom.uuid
      csv << [id, category, text]
    end
    puts "✅ Added tweet to queue under '#{category}'"
  end

  ##
  # Formats tweet text with line breaks.
  # Adds line break after the first sentence and separates hashtags.
  #
  # @param text [String] The tweet text to format
  # @return [String] The formatted tweet text
  #
  def format_tweet(text)
    formatted = text.sub('. ', ".\n\n")
    formatted.sub(/(#\w+)/, "\n\n\\1")
  end

  ##
  # Gets the current time in the specified timezone.
  #
  # @param city [String] The timezone city (default: 'Asia/Kathmandu')
  # @return [Time] The current time in the specified timezone
  #
  def my_timezone(city = 'Asia/Kathmandu')
    tz = TZInfo::Timezone.get(city)
    tz.now
  end
end
