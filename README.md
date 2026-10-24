# Everyday Citizen (everydaycitizen.vote)

Code name `the_floor`. See `CLAUDE.md` and `docs/SPEC.md`.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Ingest

The ingest pipeline pulls from Congress.gov, GovInfo, the unitedstates/congress-legislators
dataset, docs.house.gov, senate.gov (floor schedule) and Voteview (Senate roll-call votes,
because senate.gov blocks automated clients; see `docs/DECISIONS.md`). Voteview data:
Lewis, Jeffrey B., Keith Poole, Howard Rosenthal, Adam Boche, Aaron Rudkin, and Luke Sonnet.
*Voteview: Congressional Roll-Call Votes Database.* https://voteview.com/. It needs one
secret:

* `CONGRESS_GOV_API_KEY` (free, https://api.congress.gov/sign-up/). Copy `.env.example`
  to `.env` and export it before starting the app; `config/runtime.exs` reads it.

Jobs run in the app (`mix phx.server` or a release) on a nightly Oban schedule
(America/New_York): jurisdiction 02:00, members 02:10, bills 02:30, votes 02:40,
committee meetings 02:50, floor schedules 03:00, coverage checks 06:00.

* `mix the_floor.ingest` enqueues every list-level job (they run concurrently);
  `mix the_floor.ingest bills` enqueues one by name (`congress`, `members`, `bills`,
  `house_votes`, `senate_votes`, `committee_meetings`, `house_floor`, `senate_floor`,
  `relink`, `coverage`). It only enqueues, so the app must be running for the jobs to
  execute. On an empty database a single `mix the_floor.ingest` is enough: jobs whose
  prerequisites (congress sessions, members, committees) are not stored yet snooze and
  retry, and `relink` and `coverage` snooze while other ingest jobs are queued. Each
  waits at most about 2 hours, then fails; `coverage` can finish before a long backfill
  does, so re-run `mix the_floor.ingest coverage` once the backfill is done.
* `mix the_floor.coverage` prints the latest coverage check per name (stored count vs the
  source's count, `PASS`/`FAIL`) and exits non-zero if any fail. The checks are produced by
  the `coverage` job. A check whose source count could not be fetched shows `-` and `FAIL`.

The first `bills` run (no earlier successful run) loads every bill from GovInfo's
BILLSTATUS bulk zips instead of the API, then queues a text backfill from the BILLS zips.
Measured locally on 2026-10-23: 19,740 bills in under 3 minutes and 23,037 text versions in
under 3 minutes; the few entries the zips lack or cannot be read fall back to per-bill and
per-version API jobs. Bills wait for a successful `members` run. Bulk files lag the API by a
few hours; the next nightly run lists from the API with a 2-day overlap and catches up.
Later runs are incremental.

## Pages

* `/`: enter a ZIP code (or, when it is split between districts or unknown, the street or
  full address); it is used once to find the district and never stored.
* `/district/:district` remembers the district in the session and shows `/reps/:district`.
* `/reps/:district`: the district's reps, one at a time, with their activity feed
  (`?rep=<person id>&filter=all|votes|bills|law`).
* `/bills/:id` (e.g. `/bills/119-s-5`): status, your reps' part, the official summary,
  the text by section (`?version=<code>&section=<enum>`), and roll calls.
* `/this-week`: the next seven days' floor and committee items (`?mine=1` for your reps).

## One-off jobs

Run by name only, never by the full ingest (`mix the_floor.ingest <name>` locally,
`TheFloor.Release.ingest("<name>")` in production):

* `bill_summaries`: fill official summaries for bills stored before summaries were kept.
* `bill_sections`: split stored bill text into sections (500 versions per run, re-queues).
* `reclassify_actions`: re-run the action classifier over stored actions.
* `reclassify_votes`: re-type stored votes from their questions.
* `zip_districts`: load the ZIP code to district table (once per congress).

## Deploy

The app runs on Fly.io as `thefloor-vote` (region `iad`) with a Fly Postgres cluster
`thefloor-vote-db`. GitHub Actions (`.github/workflows/ci.yml`) checks formatting, credo,
warnings and tests on every push and pull request, and deploys `main` after they pass
(`flyctl deploy --remote-only`, using the `FLY_API_TOKEN` repository secret). Migrations
run as the Fly release command (`/app/bin/migrate`). One machine always runs, because
Oban runs the nightly schedule inside the app.

Secrets are Fly secrets, never in the repo: `DATABASE_URL`, `SECRET_KEY_BASE`,
`CONGRESS_GOV_API_KEY`, `PHX_HOST` (the canonical host; every other host, such as `www.`
or the Fly hostname, redirects to it), `SENTRY_DSN`.

Errors, crashes and failed jobs go to Sentry (org `thefloorvote`, project `the-floor`),
tagged with the deployed commit. Each nightly job also reports to Sentry's Crons page, which
flags a run that failed, ran long or never happened. Reports carry no request bodies,
cookies or query strings. The ingest commands have release equivalents that
run inside the live app:

    fly ssh console -C "/app/bin/the_floor rpc 'TheFloor.Release.ingest()'"
    fly ssh console -C "/app/bin/the_floor rpc 'TheFloor.Release.ingest(\"bills\")'"
    fly ssh console -C "/app/bin/the_floor rpc 'TheFloor.Release.coverage()'"

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
