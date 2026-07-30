# Security Policy

## Supported Versions

TweetX is distributed as source, not as a released gem. Security fixes land on
`main`; there are no maintained release branches. Pull the latest `main`.

## Reporting a Vulnerability

Please do **not** open a public issue for a security problem.

Report it privately through
[GitHub Security Advisories](https://github.com/cdrrazan/TweetX/security/advisories/new),
or by email to **cdrrazan@gmail.com**.

Please include what you can: what the issue is, how to reproduce it, and what an
attacker could achieve. You will get an acknowledgement within a few days. This
is a personal project maintained in spare time, so please allow reasonable time
for a fix before disclosing publicly.

## What this project touches

TweetX posts to a live X account on your behalf. That shapes what counts as a
security issue here.

**Credentials.** Four OAuth 1.0a values (`X_API_KEY`, `X_API_KEY_SECRET`,
`X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) are read from the environment via
`.env`, which is gitignored. `.env.sample` is the template and contains no real
values. If you fork this repo, check that you have not committed a real `.env`.

**The datastore is plain CSV, committed to git.** Everything in `data/` is
public in a public repo. Do not put anything in a tweet body that you would not
publish — because publishing is exactly what happens to it.

**No authentication of any kind.** This is a local CLI. Anyone with shell access
to the checkout and the `.env` file can post to your account. There is no
additional layer, and adding one is out of scope.

**CI posts for real.** If you enable the workflow in
`.github/workflows/deploy.yml.sample`, it runs hourly against your live account
using repository secrets. Read that file before enabling it, and note the
`if: github.repository ==` guard that stops forks from posting on your behalf.

## Known limitations, deliberately accepted

These are design choices of a small personal tool, not oversights. They are
listed so you can judge whether the tool fits your situation:

- Every mutation is read-all, modify-in-memory, rewrite-whole-file, with no
  locking. Concurrent writers can lose rows.
- Deduplication is by matching tweet text, not by id.
- The timezone and the hour-to-category mapping are hardcoded.
