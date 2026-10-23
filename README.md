# TheFloor

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Ingest

The ingest pipeline pulls from Congress.gov, GovInfo, the unitedstates/congress-legislators
dataset, docs.house.gov and senate.gov. It needs one secret:

* `CONGRESS_GOV_API_KEY` (free, https://api.congress.gov/sign-up/). Copy `.env.example`
  to `.env` and export it before starting the app; `config/runtime.exs` reads it.

Jobs run in the app (`mix phx.server` or a release) on a nightly Oban schedule
(America/New_York): jurisdiction 02:00, members 02:10, bills 02:30, votes 02:40,
committee meetings 02:50, floor schedules 03:00, coverage checks 06:00.

* `mix the_floor.ingest` enqueues every list-level job in dependency order;
  `mix the_floor.ingest bills` enqueues one by name (`congress`, `members`, `bills`,
  `house_votes`, `senate_votes`, `committee_meetings`, `house_floor`, `senate_floor`,
  `coverage`). It only enqueues, so the app must be running for the jobs to execute.
  On an empty database run `mix the_floor.ingest congress` and `members` first and let
  them finish before the rest.
* `mix the_floor.coverage` prints the latest coverage check per name (stored count vs the
  source's count, `PASS`/`FAIL`) and exits non-zero if any fail. The checks are produced by
  the `coverage` job. A check whose source count could not be fetched shows `-` and `FAIL`.

The first backfill is slow: about 15,000 bills at 5 requests each, limited to 4,800
requests/hour, takes roughly 16 hours. Later runs are incremental.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
