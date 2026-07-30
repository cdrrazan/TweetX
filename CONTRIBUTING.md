# Contributing to TweetX

Thanks for taking a look. TweetX is a small, deliberately simple tool: a Thor
CLI that picks one tweet per hour from a CSV file and posts it to X. Keeping it
small is a feature, so the most useful contributions are usually fixes and
sharp edges smoothed, rather than new subsystems.

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

```bash
git clone https://github.com/cdrrazan/TweetX.git
cd TweetX
bundle install          # Ruby 3.2.2, pinned in the Gemfile

cp .env.sample .env     # then fill in your four X API values
```

You do **not** need real X credentials to work on most of the codebase. The test
suite never touches the network — `X::Client.new` is stubbed globally in
`spec/spec_helper.rb`, and `preview` shows what would be posted without calling
the API.

## Running the checks

```bash
bundle exec rspec       # the suite
bundle exec rubocop     # lint; -a to autocorrect
```

Both should be clean before you open a pull request. The suite runs in well
under a second, so there is no excuse not to.

To run a single file or a single example:

```bash
bundle exec rspec spec/tweetx/scheduler_spec.rb
bundle exec rspec spec/tweetx/scheduler_spec.rb:42
```

## Things worth knowing before you change anything

**The CSV column holding tweet text is `tweet`.** Not `text`. Reading
`row['text']` returns `nil` rather than raising, so getting this wrong breaks
deduplication and both list commands silently. There is a spec pinning it.

**Category strings are compared with `==`.** The hour-to-category map in
`Scheduler#category_for_current_hour` must match `data/categories.txt` byte for
byte. A casing slip makes a whole time slot post nothing, with no error. There
is a spec pinning that too.

**`select_tweet` uses `.sample`.** Call it once and hold the result. Calling it
twice gives you two different tweets.

**The CLI never deletes the row it posted.** Deduplication is entirely by
matching text against `data/tweet_published.csv`. This is deliberate, not a
missing feature.

**Specs must never write to `data/`.** Use the `CsvFixtures` helpers, which
redirect `Scheduler`'s file constants at a temp directory. A spec that skips
this rewrites the real queue.

## The web dashboard lives elsewhere

This repo is the CLI. The Sinatra dashboard is
[TweetX-web](https://github.com/cdrrazan/TweetX-web). The two share `lib/tweetx/`
and `data/` **by copy, not by dependency** — there is no gem and no submodule. A
fix to shared code needs applying in both by hand. If you send a patch that
touches `lib/tweetx/`, say so in the PR and it will be ported.

This repo also deliberately omits the web-only `Scheduler` methods that
TweetX-web carries (`find_upcoming_by_id`, `remove_from_tweet_collection`,
`post_tweet_and_get_id_url`). Please do not "restore" them without a CLI caller.

## Pull requests

- Branch off `main`. Please don't commit to `main` directly.
- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`,
  `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `style:`, `ci:`.
- Explain **why** in the description, not just what. The diff already says what.
- Add a spec for behaviour changes and bug fixes.
- Keep `bundle exec rspec` and `bundle exec rubocop` clean.

## Reporting bugs

Open an issue with what you ran, what you expected, and what happened. If it
involves scheduling, include the hour and timezone — a surprising number of
issues in a tool like this turn out to be the hour-to-category map.

Security issues go through [SECURITY.md](SECURITY.md) instead, not the issue
tracker.
