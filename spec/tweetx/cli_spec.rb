# frozen_string_literal: true

require_relative '../../lib/tweetx'

RSpec.describe Tweetx::CLI do
  # Every command is a one-line delegation to Scheduler, so that delegation —
  # and nothing else — is what these specs pin down.
  let(:scheduler) { instance_double(Scheduler) }

  before { allow(Scheduler).to receive(:new).and_return(scheduler) }

  it 'runs the scheduler for `tweet`' do
    allow(scheduler).to receive(:run)

    described_class.start(['tweet'])

    expect(scheduler).to have_received(:run)
  end

  it 'previews for `preview`' do
    allow(scheduler).to receive(:preview)

    described_class.start(['preview'])

    expect(scheduler).to have_received(:preview)
  end

  it 'lists unpublished tweets for `list`' do
    allow(scheduler).to receive(:list_tweets)

    described_class.start(['list'])

    expect(scheduler).to have_received(:list_tweets)
  end

  it 'lists published tweets for `archive`' do
    allow(scheduler).to receive(:list_published)

    described_class.start(['archive'])

    expect(scheduler).to have_received(:list_published)
  end

  it 'passes text and category through for `add`' do
    allow(scheduler).to receive(:add_tweet)

    described_class.start(['add', 'Some text', 'Devtip'])

    expect(scheduler).to have_received(:add_tweet).with('Some text', 'Devtip')
  end

  it 'exposes exactly the five documented commands, plus Thor\'s own help' do
    expect(described_class.all_commands.keys).to match_array(%w[tweet preview list add archive help])
  end
end
