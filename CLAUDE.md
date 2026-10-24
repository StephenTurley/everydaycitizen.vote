# Everyday Citizen — everydaycitizen.vote

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

- Name: **Everyday Citizen** (renamed from The Floor on 2026-10-24, before
  launch). Domain `everydaycitizen.vote`, registered at Namecheap, served by the
  Fly.io app `thefloor-vote` (iad); every other host (`www.`, the old
  `thefloor.vote`, `thefloor-vote.fly.dev`) redirects to it. Errors go to Sentry
  (`thefloorvote/the-floor`). Fly and Sentry names keep the old name (Fly apps
  cannot be renamed).
- GitHub repo `StephenTurley/everydaycitizen.vote`. Elixir app name
  `everyday_citizen`; modules `EverydayCitizen` (domain) and `EverydayCitizenWeb`
  (LiveView); renamed from `the_floor`/`TheFloor` on 2026-10-24. The local dev
  and test databases are still named `the_floor_dev`/`the_floor_test`.
- Production commands: `fly ssh console -C "/app/bin/everyday_citizen rpc
  'EverydayCitizen.Release.ingest(\"name\")'"` (and `.coverage()`).
- Product direction: plain-language understanding of what your reps do now;
  later, proposals that citizens second and send to their own reps (SPEC §9).

## Non-negotiables

- No UI or domain code may know it is federal. Jurisdiction-specific logic lives
  only in adapters (`lib/everyday_citizen/adapters/<jurisdiction>/`). The schema is
  the contract.
- Every record carries provenance: source URL, `fetched_at`, content hash.
- Plain-language output is always clause-anchored and rendered beside the source
  text. Never show a summary without the text it came from.
- The product never explains "why" in its own voice. Every argument is labeled
  with who made it (CRS, committee report, sponsor, CBO, opposing statement).
- Expensive layers (plain-language, redline, why-panel) run only on bills that
  meet the movement filter defined in the spec.

## Current milestone

M2 (see `docs/SPEC.md` → Milestones), designed in
`docs/superpowers/specs/2026-10-23-m2-frontend-design.md`. M2a (public pages: find
your reps, rep feed, bill page, this week) and M2b (accounts with email link and
passkeys, following, daily email) are built; M2 is done once a person can find
their reps and follow a bill end to end in production. Next is M3 (plain-language
layer). M1 (schema + federal adapter) is done.

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
  under `lib/everyday_citizen/` with LiveViews under `lib/everyday_citizen_web/`.
- Oban for scheduled and incremental ingest jobs.
- Req for HTTP; Saxy (streaming) for USLM bill text and US Code XML, which
  are large.
- Adapters live in `lib/everyday_citizen/adapters/<jurisdiction>/` and only produce
  structs that match the schema.

## Build and test

- `mix setup` — deps, database, assets
- `mix phx.server` — run locally at http://localhost:4000
- `mix everyday_citizen.ingest [job]` — enqueue the ingest jobs (all, or one by name)
- `mix everyday_citizen.coverage` — print latest coverage checks; non-zero exit on any failure
- `mix test` — run before every commit
- `mix format` and `mix credo` before opening a PR

Run `/init` after the first real code lands to fill in anything above that
drifts.
