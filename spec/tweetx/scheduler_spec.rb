# frozen_string_literal: true

require 'json'
require_relative '../../lib/tweetx/scheduler'

RSpec.describe Scheduler do
  subject(:scheduler) { described_class.new }

  let(:fake_client) { scheduler.instance_variable_get(:@client) }

  before do
    point_scheduler_at_fixtures
    write_collection([])
    write_published([])
  end

  # Freezes the scheduler's clock at a given hour in the configured timezone.
  def at_hour(hour)
    allow(scheduler).to receive(:my_timezone).and_return(Time.new(2026, 7, 30, hour, 0, 0))
  end

  # select_tweet prints a status line as a side effect. This swallows that so
  # the suite's own output stays readable, and returns what the method returned.
  def select_tweet_quietly
    result = nil
    capture_stdout { result = scheduler.select_tweet }
    result
  end

  # Same idea for run, whose return value is what the CLI exits on.
  def run_quietly(**options)
    result = nil
    capture_stdout { result = scheduler.run(**options) }
    result
  end

  describe '#category_for_current_hour' do
    {
      5 => 'Motivation', 8 => 'Motivation',
      9 => 'Devtip', 12 => 'Devtip',
      13 => 'Branding', 16 => 'Branding',
      17 => 'Builtwith', 20 => 'Builtwith',
      21 => 'Ebook', 23 => 'Ebook'
    }.each do |hour, category|
      it "maps hour #{hour} to #{category}" do
        at_hour(hour)

        expect(scheduler.category_for_current_hour).to eq(category)
      end
    end

    (0..4).each do |hour|
      it "posts nothing at hour #{hour}" do
        at_hour(hour)

        expect(scheduler.category_for_current_hour).to be_nil
      end
    end

    it 'only returns categories that exist in data/categories.txt' do
      # These strings are compared with == against the CSV category column, so a
      # casing slip here silently makes a whole time slot post nothing. This is
      # the regression that made the 17:00-20:00 slot dead when the code said
      # 'BuiltWith' and the data said 'Builtwith'.
      known = File.read(File.join(described_class::DATA_DIR, 'categories.txt')).split("\n").map(&:strip)
      mapped = (0..23).filter_map { |hour| at_hour(hour) && scheduler.category_for_current_hour }.uniq

      expect(known).to include(*mapped)
    end
  end

  describe '#valid_tweet?' do
    it 'accepts ordinary text' do
      expect(scheduler.valid_tweet?('a normal tweet')).to be true
    end

    it 'accepts text of exactly 280 characters' do
      expect(scheduler.valid_tweet?('x' * 280)).to be true
    end

    it 'rejects text longer than 280 characters' do
      expect(scheduler.valid_tweet?('x' * 281)).to be false
    end

    it 'rejects whitespace-only text' do
      expect(scheduler.valid_tweet?("  \n ")).to be false
    end

    it 'rejects nil' do
      expect(scheduler.valid_tweet?(nil)).to be false
    end
  end

  describe '#select_tweet' do
    before { at_hour(10) } # Devtip

    it 'returns a category and body from the current slot' do
      write_collection([['1', 'Devtip', 'Use bundle exec']])

      expect(select_tweet_quietly).to eq(['Devtip', 'Use bundle exec'])
    end

    it 'reads the body from the tweet column' do
      # Scheduler used to read row['text'], which returns nil for these files
      # and silently broke dedup and both list commands.
      write_collection([['1', 'Devtip', 'Body text']])

      expect(select_tweet_quietly.last).to eq('Body text')
    end

    it 'ignores tweets from other categories' do
      write_collection([['1', 'Ebook', 'Wrong slot']])

      expect(select_tweet_quietly).to be_nil
    end

    it 'ignores tweets whose text already appears in the archive' do
      write_collection([['1', 'Devtip', 'Already posted']])
      write_published([['99', 'Devtip', 'Already posted', '2026-07-30T00:00:00Z']])

      expect(select_tweet_quietly).to be_nil
    end

    it 'returns nil outside posting hours' do
      at_hour(3)
      write_collection([%w[1 Devtip Anything]])

      expect(select_tweet_quietly).to be_nil
    end

    it 'returns nil when the queue file is missing' do
      FileUtils.rm_f(collection_path)

      expect(scheduler.select_tweet).to be_nil
    end
  end

  describe '#run' do
    before do
      at_hour(10)
      write_collection([['1', 'Devtip', 'Ship it']])
    end

    it 'posts the formatted tweet to the API' do
      capture_stdout { scheduler.run }

      expect(fake_client.last_posted_text).to eq(scheduler.format_tweet('Ship it'))
    end

    it 'records the posted tweet in the archive' do
      capture_stdout { scheduler.run }

      expect(read_rows(published_path).last).to include('category' => 'Devtip', 'tweet' => 'Ship it')
    end

    it 'stores the id returned by the API' do
      capture_stdout { scheduler.run }

      expect(read_rows(published_path).last['id']).to eq(FakeXClient::DEFAULT_TWEET_ID)
    end

    it 'leaves the posted row in the queue' do
      # Only POST /tweet-now/:id removes rows; the cron path relies on
      # text-matching against the archive instead, so the queue only grows.
      capture_stdout { scheduler.run }

      expect(read_rows(collection_path).size).to eq(1)
    end

    it 'selects a tweet exactly once per run' do
      # select_tweet uses .sample. Calling it repeatedly picked three different
      # rows and archived a category that did not match the posted body.
      allow(scheduler).to receive(:select_tweet).and_call_original

      capture_stdout { scheduler.run }

      expect(scheduler).to have_received(:select_tweet).once
    end

    it 'archives the category belonging to the tweet it posted' do
      write_collection([%w[1 Devtip One], %w[2 Devtip Two], %w[3 Devtip Three]])

      capture_stdout { scheduler.run }

      row = read_rows(published_path).last
      expect(fake_client.last_posted_text).to eq(scheduler.format_tweet(row['tweet']))
    end

    it 'does not post when nothing is available' do
      write_collection([])

      capture_stdout { scheduler.run }

      expect(fake_client.posts).to be_empty
    end

    it 'skips a tweet that exceeds the character limit' do
      write_collection([['1', 'Devtip', 'x' * 300]])

      capture_stdout { scheduler.run }

      expect(fake_client.posts).to be_empty
    end

    it 'reports the skip so the operator knows why nothing went out' do
      write_collection([['1', 'Devtip', 'x' * 300]])

      expect(capture_stdout { scheduler.run }).to include('Skipping invalid tweet')
    end

    it 'does not call the API on a dry run' do
      capture_stdout { scheduler.run(dry_run: true) }

      expect(fake_client.posts).to be_empty
    end

    it 'shows what a dry run would have posted' do
      expect(capture_stdout { scheduler.run(dry_run: true) }).to include('[DRY RUN]', 'Ship it')
    end

    it 'does not archive anything on a dry run' do
      capture_stdout { scheduler.run(dry_run: true) }

      expect(read_rows(published_path)).to be_empty
    end

    it 'survives an API failure without archiving the tweet' do
      fake_client.raise_on_post = 'rate limited'

      capture_stdout { scheduler.run }

      expect(read_rows(published_path)).to be_empty
    end

    it 'reports an API failure' do
      fake_client.raise_on_post = 'rate limited'

      expect(capture_stdout { scheduler.run }).to include('Failed to tweet', 'rate limited')
    end

    describe 'the return value, which the CLI turns into an exit status' do
      it 'is true when the tweet was posted' do
        expect(run_quietly).to be(true)
      end

      it 'is false when the API rejects the post' do
        fake_client.raise_on_post = 'rate limited'

        expect(run_quietly).to be(false)
      end

      it 'is true when there is simply nothing to post' do
        # Every night between 00:00 and 05:00. Not a failure — the scheduled
        # job must not go red for it.
        write_collection([])

        expect(run_quietly).to be(true)
      end

      it 'is true on a dry run' do
        expect(run_quietly(dry_run: true)).to be(true)
      end

      it 'is true when the tweet is skipped as invalid' do
        write_collection([['1', 'Devtip', 'x' * 300]])

        expect(run_quietly).to be(true)
      end
    end

    context 'when the API answers 2xx but returns no tweet id' do
      before { fake_client.next_response = { 'data' => {} } }

      it 'does not claim success' do
        expect(capture_stdout { scheduler.run }).to include('returned no tweet id')
      end

      it 'does not archive the tweet' do
        capture_stdout { scheduler.run }

        expect(read_rows(published_path)).to be_empty
      end

      it 'reports failure to the caller' do
        expect(run_quietly).to be(false)
      end
    end
  end

  describe '#send_to_published' do
    it 'writes a header row to an empty archive' do
      FileUtils.rm_f(published_path)

      scheduler.send_to_published('42', 'Devtip', 'Body')

      expect(CSV.read(published_path).first).to eq(%w[id category tweet timestamp])
    end

    it 'stores the body under the tweet column' do
      FileUtils.rm_f(published_path)

      scheduler.send_to_published('42', 'Devtip', 'Body')

      expect(read_rows(published_path).last['tweet']).to eq('Body')
    end

    it 'timestamps the row in UTC ISO8601' do
      FileUtils.rm_f(published_path)

      scheduler.send_to_published('42', 'Devtip', 'Body')

      expect(read_rows(published_path).last['timestamp']).to match(/\A\d{4}-\d{2}-\d{2}T[\d:]{8}Z\z/)
    end

    it 'appends without duplicating the header' do
      write_published([['1', 'Devtip', 'First', '2026-07-30T00:00:00Z']])

      scheduler.send_to_published('2', 'Devtip', 'Second')

      expect(read_rows(published_path).map { |row| row['tweet'] }).to eq(%w[First Second])
    end
  end

  describe '#published_tweets' do
    it 'returns the body of every archived tweet' do
      write_published([['1', 'Devtip', 'Archived', '2026-07-30T00:00:00Z']])

      expect(scheduler.published_tweets).to eq(['Archived'])
    end

    it 'returns an empty list when the archive is missing' do
      FileUtils.rm_f(published_path)

      expect(scheduler.published_tweets).to eq([])
    end
  end

  describe '#add_tweet' do
    it 'appends the tweet to the queue' do
      capture_stdout { scheduler.add_tweet('Fresh idea', 'Devtip') }

      expect(read_rows(collection_path).last).to include('category' => 'Devtip', 'tweet' => 'Fresh idea')
    end

    it 'gives the new row an id' do
      capture_stdout { scheduler.add_tweet('Fresh idea', 'Devtip') }

      expect(read_rows(collection_path).last['id']).not_to be_empty
    end

    it 'writes a header row when the queue is empty' do
      FileUtils.rm_f(collection_path)

      capture_stdout { scheduler.add_tweet('Fresh idea', 'Devtip') }

      expect(CSV.read(collection_path).first).to eq(%w[id category tweet])
    end
  end

  describe '#list_tweets' do
    it 'lists the body of each unpublished tweet' do
      write_collection([%w[1 Devtip Unpublished]])

      expect(capture_stdout { scheduler.list_tweets }).to include('Unpublished')
    end

    it 'labels each tweet with its category' do
      write_collection([%w[1 Devtip Unpublished]])

      expect(capture_stdout { scheduler.list_tweets }).to include('[Devtip]')
    end

    it 'hides tweets that already appear in the archive' do
      write_collection([%w[1 Devtip Gone]])
      write_published([['9', 'Devtip', 'Gone', '2026-07-30T00:00:00Z']])

      expect(capture_stdout { scheduler.list_tweets }).to include('No unpublished tweets found')
    end
  end

  describe '#list_published' do
    it 'lists archived tweet bodies' do
      write_published([['1', 'Devtip', 'Archived body', '2026-07-30T00:00:00Z']])

      expect(capture_stdout { scheduler.list_published }).to include('Archived body')
    end

    it 'says so when nothing has been published' do
      FileUtils.rm_f(published_path)

      expect(capture_stdout { scheduler.list_published }).to include('No published tweets yet')
    end
  end

  describe '#preview' do
    before { at_hour(10) }

    it 'shows the formatted tweet' do
      write_collection([['1', 'Devtip', 'Ship it. Now #ruby']])

      expect(capture_stdout { scheduler.preview }).to include(scheduler.format_tweet('Ship it. Now #ruby'))
    end

    it 'never calls the API' do
      write_collection([['1', 'Devtip', 'Ship it']])

      capture_stdout { scheduler.preview }

      expect(fake_client.posts).to be_empty
    end

    it 'says so when there is nothing to preview' do
      expect(capture_stdout { scheduler.preview }).to include('No tweet available to preview')
    end
  end

  # This repo deliberately omits the web-only methods TweetX-web's Scheduler
  # carries — find_upcoming_by_id, remove_from_tweet_collection and
  # post_tweet_and_get_id_url. There is no CLI caller for them, so there is
  # nothing here to cover.

  describe 'missing credentials' do
    # X answers a request signed with blank credentials exactly as it answers
    # one signed with revoked credentials: 401 "Unauthorized". These examples
    # exist so the two are distinguishable from the output alone.
    before do
      at_hour(10)
      write_collection([['1', 'Devtip', 'Ship it']])
      stub_const('Scheduler::REQUIRED_CREDENTIALS', %w[X_API_KEY X_ACCESS_TOKEN])
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('X_ACCESS_TOKEN', nil).and_return('')
    end

    it 'names the credential that is missing' do
      expect(capture_stdout { scheduler.run }).to include('X_ACCESS_TOKEN')
    end

    it 'does not name a credential that is present' do
      expect(capture_stdout { scheduler.run }).not_to include('X_API_KEY,')
    end

    it 'says where the value should come from' do
      expect(capture_stdout { scheduler.run }).to include('repository secrets')
    end

    it 'never calls the API' do
      capture_stdout { scheduler.run }

      expect(fake_client.posts).to be_empty
    end

    it 'reports failure so the job goes red' do
      expect(run_quietly).to be(false)
    end
  end

  describe '#credential_hint' do
    it 'explains a 401 as a credential problem' do
      expect(scheduler.credential_hint(401)).to include('rejected the credentials')
    end

    it 'explains a 403 as a permissions problem' do
      expect(scheduler.credential_hint(403)).to include('Read and Write')
    end

    it 'says nothing for unrelated statuses' do
      expect(scheduler.credential_hint(500)).to eq('')
    end
  end

  describe '#format_tweet' do
    it 'breaks the paragraph after the first sentence' do
      expect(scheduler.format_tweet('One. Two. Three.')).to eq("One.\n\nTwo. Three.")
    end

    it 'moves the first hashtag onto its own line' do
      expect(scheduler.format_tweet('Ship it #ruby')).to eq("Ship it \n\n#ruby")
    end

    it 'applies both rules together' do
      expect(scheduler.format_tweet('Built a thing. It posts tweets #ruby'))
        .to eq("Built a thing.\n\nIt posts tweets \n\n#ruby")
    end

    it 'leaves text without a period or hashtag alone' do
      expect(scheduler.format_tweet('no punctuation here')).to eq('no punctuation here')
    end

    it 'does not break on a period that is not followed by a space' do
      expect(scheduler.format_tweet('rspec-3.13 is out')).to eq('rspec-3.13 is out')
    end

    it 'returns an empty string unchanged' do
      expect(scheduler.format_tweet('')).to eq('')
    end
  end

  describe '#my_timezone' do
    it 'defaults to Asia/Kathmandu' do
      expect(scheduler.my_timezone.strftime('%Z')).to eq('+0545')
    end

    it 'accepts another timezone' do
      expect(scheduler.my_timezone('UTC').strftime('%Z')).to eq('UTC')
    end
  end
end
