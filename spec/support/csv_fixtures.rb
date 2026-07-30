# frozen_string_literal: true

# Helpers for pointing Scheduler at throwaway CSV files.
#
# Scheduler reads and writes data/*.csv through absolute constants derived from
# ROOT_DIR, so every spec that touches the datastore MUST redirect them. Without
# this the suite would rewrite the real tweet queue in data/.
module CsvFixtures
  COLLECTION_HEADERS = %w[id category tweet].freeze
  PUBLISHED_HEADERS = %w[id category tweet timestamp].freeze

  # Temporary directory for the current example, created on first use.
  # @return [String] path to the directory
  def fixture_dir
    @fixture_dir ||= Dir.mktmpdir('tweetx-spec')
  end

  # @return [String] path the queue CSV is written to for this example
  def collection_path
    File.join(fixture_dir, 'tweet_collection.csv')
  end

  # @return [String] path the archive CSV is written to for this example
  def published_path
    File.join(fixture_dir, 'tweet_published.csv')
  end

  # Writes the unpublished queue.
  # @param rows [Array<Array>] rows of [id, category, tweet]
  # @return [String] the path written
  def write_collection(rows)
    write_csv(collection_path, COLLECTION_HEADERS, rows)
  end

  # Writes the published archive.
  # @param rows [Array<Array>] rows of [id, category, tweet, timestamp]
  # @return [String] the path written
  def write_published(rows)
    write_csv(published_path, PUBLISHED_HEADERS, rows)
  end

  # Reads a CSV back as an array of hashes.
  # @param path [String]
  # @return [Array<Hash>]
  def read_rows(path)
    return [] unless File.exist?(path)

    CSV.read(path, headers: true).map(&:to_h)
  end

  # Redirects Scheduler's absolute file constants at the fixture directory.
  # @return [void]
  def point_scheduler_at_fixtures
    stub_const('Scheduler::TWEET_COLLECTION_FILE', collection_path)
    stub_const('Scheduler::TWEET_PUBLISHED_FILE', published_path)
  end

  private

  def write_csv(path, headers, rows)
    CSV.open(path, 'w') do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
    path
  end
end

RSpec.configure do |config|
  # Each example gets its own directory; drop it afterwards so the suite leaves
  # nothing behind in the system temp dir.
  config.after do
    FileUtils.remove_entry(@fixture_dir) if @fixture_dir && File.directory?(@fixture_dir)
  end
end
