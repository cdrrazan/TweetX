# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TweetX — the **CLI half** of the project. A Thor command-line tweet scheduler backed by CSV files. No database, no web server, no test suite.

The web dashboard lives in a separate repository, **TweetX-web**. The two share `lib/tweetx/` and `data/` by copy, not by dependency, so a fix here usually needs porting there.

## Commands

```bash
bundle install                       # deps (Ruby 3.2.2 pinned in Gemfile)

bundle exec ruby bin/tweetx tweet    # pick + post one tweet for the current time slot
bundle exec ruby bin/tweetx preview  # show what `tweet` would post, no API call
bundle exec ruby bin/tweetx list     # unpublished tweets
bundle exec ruby bin/tweetx archive  # published tweets
bundle exec ruby bin/tweetx add "text" Category
```

No tests and no linter. Verification is manual — `preview` and `Scheduler#run(dry_run: true)` exercise selection and formatting without hitting the X API.

## Architecture

- **`bin/tweetx`** — executable; requires `lib/tweetx` and calls `Tweetx::CLI.start`.
- **`lib/tweetx/cli.rb`** — Thor wrapper. Every command is a one-line delegation to `Scheduler`.
- **`lib/tweetx/scheduler.rb`** — all the logic and the only X API client. Paths are absolute, derived from `ROOT_DIR`, so commands work from any CWD.

This repo deliberately **omits** the web-only scheduler methods that TweetX-web has (`find_upcoming_by_id`, `remove_from_tweet_collection`, `post_tweet_and_get_id_url`). That is intentional divergence, not drift — don't "restore" them without a CLI caller.

### Datastore

Plain CSV under `data/`, committed to git:

| File | Headers | Role |
|---|---|---|
| `tweet_collection.csv` | `id,category,tweet` | queue of unpublished tweets |
| `tweet_published.csv` | `id,category,tweet,timestamp` | archive; `id` is the X tweet ID, `timestamp` is UTC ISO8601 |
| `categories.txt` | newline-delimited | category list |

The column holding body text is `tweet` everywhere. It was previously read and written as `text` in this file, which silently broke dedup and both list commands; if you see `row['text']`, it's a regression.

`bin/tweetx tweet` **never removes the posted row** from `tweet_collection.csv`. Dedup is purely by matching tweet text against `tweet_published.csv`, so the queue file only grows.

### Scheduling

`Scheduler#category_for_current_hour` maps the hour in **Asia/Kathmandu** (hardcoded default in `my_timezone`) to a category:

```
5–8 Motivation | 9–12 Devtip | 13–16 Branding | 17–20 Builtwith | 21–23 Ebook
```

Compared to the CSV `category` column with `==`, so these must match `data/categories.txt` byte for byte — a casing slip silently makes a whole time slot post nothing. Hours 0–4 map to `nil`. A random unpublished tweet from the matching category is chosen; empty or >280 chars is skipped.

## Environment

`.env` is gitignored; `.env.sample` is the template. This CLI reads only the four OAuth 1.0a values (`X_API_KEY`, `X_API_KEY_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`). The bearer/client vars are kept in the sample for reference but unused, and `X_USERNAME` / `TWEETX_USER` / `TWEETX_PASS` belong to TweetX-web.

## Deployment

`.github/workflows/deploy.yml.sample` is **inert** — GitHub only reads `.yml`. The header comment covers activation. Note it needs `fetch-depth: 0` (shallow clones can't merge or push) and carries a `concurrency` group; scheduled workflows only fire from the default branch.
