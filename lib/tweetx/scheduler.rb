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
  # Main runner method that posts a tweet.
  # Selects an appropriate tweet based on current time and posts it to X/Twitter.
  #
  # @param dry_run [Boolean] If true, only previews the tweet without posting
  # @return [void]
  #
  def run(dry_run: false)
    selected = select_tweet

    if selected.nil?
      puts '🚫 No text available to tweet.'
      return
    end

    category, tweet = selected

    formatted_tweet = format_tweet(tweet)
    unless valid_tweet?(formatted_tweet)
      puts "⚠️ Skipping invalid tweet (empty or >280 characters): #{formatted_tweet.inspect}"
      return
    end

    if dry_run
      puts "🤖 [DRY RUN] Would tweet:\n#{formatted_tweet}"
      return
    end

    begin
      response = @client.post('tweets', { text: formatted_tweet }.to_json)

      if response.dig(:data, :id) || response.dig('data', 'id')
        obj_id = response.dig(:data, :id) || response.dig('data', 'id')
        puts "✅ Tweeted: #{tweet}"
        send_to_published(obj_id, category, tweet)
      else
        puts "❌ Failed to tweet: #{response.status} - #{response.body}"
      end
    rescue StandardError => e
      puts "❌ Failed to tweet: #{e.message}"
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
    puts "🕒 Current hour: #{Time.now.hour} → Category: #{category || 'unspecified'}"

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
