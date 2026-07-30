# 🐦 TweetX

_— Your Developer-First Tweet Automation Toolkit_

**TweetX** is a lightweight tweet scheduler for coders, writers, and creators who want to stay consistent without the hassle. Write your tweets once, sort them into categories, and let a cron job post one every hour.

> ✅ A clean Ruby CLI, a CSV file, and a GitHub Action. That's the whole system.

This repo is the **CLI**. The web dashboard lives in [TweetX-web](https://github.com/cdrrazan/TweetX-web) — see [Two repos, one tool](#-two-repos-one-tool) below.

## 💡 What it does

- ✍️ Keep a queue of tweets, tagged by category
- 🕒 Post one per hour, picked from the category that matches the current time slot
- 💾 Store everything in CSV — no database, no ORM, no migrations
- 🌍 Schedule in your own timezone (Asia/Kathmandu by default)
- 🐙 Run it from GitHub Actions and commit the published history back

It's a tweet CMS and bot for devs. Build once, automate forever.

## 🚀 Getting started

```bash
git clone https://github.com/cdrrazan/TweetX.git
cd TweetX
bundle install            # Ruby 3.2.2, pinned in the Gemfile

cp .env.sample .env       # then add your X API credentials
```

You need four OAuth 1.0a values from the [X developer portal](https://developer.x.com/):

```
X_API_KEY=
X_API_KEY_SECRET=
X_ACCESS_TOKEN=
X_ACCESS_TOKEN_SECRET=
```

`.env` is gitignored. The other variables in `.env.sample` are documented there — most belong to TweetX-web, and a few are kept for reference but unused.

## 🖥 Commands

```bash
bundle exec ruby bin/tweetx preview            # what the next run would post — no API call
bundle exec ruby bin/tweetx tweet              # pick and post one tweet for the current slot
bundle exec ruby bin/tweetx list               # unpublished tweets
bundle exec ruby bin/tweetx archive            # published tweets
bundle exec ruby bin/tweetx add "text" Devtip  # queue a new tweet
```

Start with `preview`. It runs the whole selection path and prints exactly what `tweet` would send, without touching the API.

## 🧪 Tests and linting

```bash
bundle exec rspec       # 72 examples
bundle exec rubocop     # -a to autocorrect
```

Both are clean on `main`. The suite never touches the network — the X client is stubbed globally, so no test can post a tweet even with real credentials in your environment.

## 🕒 How scheduling works

The hour, in your configured timezone, decides the category:

| Hours | Category |
|---|---|
| 05–08 | Motivation |
| 09–12 | Devtip |
| 13–16 | Branding |
| 17–20 | Builtwith |
| 21–23 | Ebook |
| 00–04 | nothing posts overnight |

A random unpublished tweet from the matching category is chosen. Anything empty or over 280 characters is skipped.

Two things worth knowing:

- **Category names are matched exactly.** These strings are compared with `==` against `data/categories.txt`. A casing slip makes a whole time slot post nothing, silently.
- **Posting does not remove the tweet from the queue.** Deduplication works by matching tweet text against `data/tweet_published.csv`, so `tweet_collection.csv` only grows. This is deliberate.

## 📂 Layout

```
TweetX/
├── bin/tweetx                        # executable
├── lib/tweetx/cli.rb                 # Thor commands — one-line delegations
├── lib/tweetx/scheduler.rb           # selection, formatting, CSV IO, the X client
├── data/tweet_collection.csv         # the queue        (id, category, tweet)
├── data/tweet_published.csv          # the archive      (+ timestamp)
├── data/categories.txt               # category list
├── spec/                             # RSpec suite
└── .github/workflows/deploy.yml.sample
```

## 🐙 Automating it

`.github/workflows/deploy.yml.sample` is a ready-to-use hourly workflow. It is **inert** — GitHub only reads `.yml` files — so rename it to activate, and read the header comment first. In short:

1. Rename to `.github/workflows/deploy.yml`
2. Add your four `X_*` values as repository secrets
3. Replace `OWNER/REPO` in the `if:` guard, which is what stops forks from posting on your behalf

It runs at `0 * * * *` UTC, posts one tweet, and commits the updated archive to a long-lived `publish-tweetx` branch. Note that scheduled workflows only fire from the default branch.

## 🧩 Two repos, one tool

| Repo | What it is |
|---|---|
| **TweetX** (here) | the CLI and the scheduler |
| [TweetX-web](https://github.com/cdrrazan/TweetX-web) | the Sinatra dashboard for browsing and editing the queue |

They share `lib/tweetx/` and `data/` **by copy, not by dependency** — no gem, no submodule. A fix to shared code needs applying in both. This repo also deliberately omits the web-only scheduler methods that TweetX-web carries.

## 📦 Built with

Ruby 3.2 · [Thor](https://github.com/rails/thor) · [x](https://github.com/sferik/x-ruby) · TZInfo · CSV · RSpec · RuboCop

## 🙌 Contributing

Pull requests welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first — it lists the handful of things in this codebase that break silently rather than loudly. Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Found a security issue? Please don't open an issue — see [SECURITY.md](SECURITY.md).

## 📘 Ideas for later

Thread support · tweet analytics · AI-assisted drafting · multi-account

## 👨‍💻 Created by

[Rajan Bhattarai](https://github.com/cdrrazan) — Ruby developer, product hacker, open-source enthusiast.

## 📜 License

[MIT](LICENSE) — free for personal and commercial use.

> ⭐ Star the project if it helps you.
