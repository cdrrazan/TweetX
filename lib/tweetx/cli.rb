# frozen_string_literal: true

module Tweetx
  ##
  # Command-line interface for TweetX.
  # Provides CLI commands using the Thor gem for tweet management and scheduling.
  #
  class CLI < Thor
    ##
    # Posts a tweet based on the current time and category.
    # Automatically selects an appropriate tweet from the collection.
    #
    desc 'tweet', 'Tweet based on current time and category'
    def tweet
      Scheduler.new.run
    end

    ##
    # Previews which tweet would be posted based on current time and category.
    # Does not actually post anything.
    #
    desc 'preview', 'Preview tweets based on current time and category'
    def preview
      Scheduler.new.preview
    end

    ##
    # Lists all unpublished tweets across all categories.
    # Shows tweets that are available to be posted.
    #
    desc 'list', 'List unpublished tweets in all categories'
    def list
      Scheduler.new.list_tweets
    end

    ##
    # Adds a new tweet to the specified category.
    #
    # @param text [String] The tweet text content
    # @param category [String] The category to add the tweet to
    #
    desc 'add TEXT CATEGORY', 'Add a new tweet to the Category'
    def add(text, category)
      Scheduler.new.add_tweet(text, category)
    end

    ##
    # Lists all previously published tweets.
    # Shows the archive of all tweets that have been posted.
    #
    desc 'archive', 'List all published tweets'
    def archive
      Scheduler.new.list_published
    end
  end
end
