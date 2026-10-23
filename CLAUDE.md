# The Floor — thefloor.vote

Read-only tool that shows constituents what Congress is voting on, who is voting,
what a bill actually changes in current law (redline against the statute), and why
(attributed arguments, never the platform's own voice). Federal first, built on a
jurisdiction-agnostic data model so state and local legislatures plug in later as
adapters.

Full spec: @docs/SPEC.md
Decision log: `docs/DECISIONS.md` (append; never rewrite history)

<!-- Remove the SPEC import above once the codebase carries this context on its
     own. Keep this file under 200 lines. -->

## Project facts

- Name: **The Floor**. Domain `thefloor.vote`, registered at Namecheap
  (2026-10-23). DNS not yet pointed anywhere.
- Elixir app name `the_floor`; modules `TheFloor` (domain) and `TheFloorWeb`
  (LiveView). Generated with `mix phx.new the_floor`.

## Non-negotiables

- No UI or domain code may know it is federal. Jurisdiction-specific logic lives
  only in adapters (`lib/the_floor/adapters/<jurisdiction>/`). The schema is
  the contract.
- Every record carries provenance: source URL, `fetched_at`, content hash.
- Plain-language output is always clause-anchored and rendered beside the source
  text. Never show a summary without the text it came from.
- The product never explains "why" in its own voice. Every argument is labeled
  with who made it (CRS, committee report, sponsor, CBO, opposing statement).
- Expensive layers (plain-language, redline, why-panel) run only on bills that
  meet the movement filter defined in the spec.

## Current milestone

M1: schema + federal adapter. See `docs/SPEC.md` → Milestones.

## Working conventions

- For anything larger than a single function, propose the plan first and wait
  for review before writing code.
- Adapters are thin: fetch → normalize to schema → write. No business logic.
- Prefer official primary sources (Congress.gov API, GovInfo, OLRC US Code XML,
  Census Geocoder) over third-party aggregators.
- Record each schema or architecture decision in `docs/DECISIONS.md` with a
  date and a one-line rationale.
- A milestone is done only when the coverage checks in the spec pass.
- Secrets (Congress.gov API key, etc.) come from environment variables read in
  `config/runtime.exs`. Never commit them. Document each new one in `.env.example`.

## Stack

- Elixir 1.20 / OTP 29 (pinned in `.tool-versions` for asdf), Phoenix 1.8 with LiveView for all UI. No separate JS
  frontend; keep client-side JS to LiveView hooks only.
- Ecto + PostgreSQL. The schema in `docs/SPEC.md` §4 maps to Ecto schemas
  under `lib/the_floor/` with LiveViews under `lib/the_floor_web/`.
- Oban for scheduled and incremental ingest jobs.
- Req for HTTP; Saxy (streaming) for USLM bill text and US Code XML, which
  are large.
- Adapters live in `lib/the_floor/adapters/<jurisdiction>/` and only produce
  structs that match the schema.

## Build and test

- `mix setup` — deps, database, assets
- `mix phx.server` — run locally at http://localhost:4000
- `mix test` — run before every commit
- `mix format` and `mix credo` before opening a PR

Run `/init` after the first real code lands to fill in anything above that
drifts.
