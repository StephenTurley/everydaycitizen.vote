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
- Expensive layers run only on bills that meet the movement filter defined in
  the spec, except plain-language summaries: those run on any bill, but only
  when someone opens the section, cached and inside a daily budget, never on
  the corpus in bulk (owner's decision, 2026-10-24). Redline and the why-panel
  keep the movement filter until decided otherwise.

## Current milestone

M3, the plain-language layer (`docs/superpowers/plans/2026-10-24-m3-plain-language-summaries.md`,
then `docs/superpowers/plans/2026-10-24-m3b-bill-and-week-summaries.md`):
plain-English summaries of bill sections, of each whole bill (above its text)
and of a rep's week (on the reps page), written by Claude the first time someone
views them and cached, labeled as AI-written beside their source, inside a
$2-a-day budget, with the prompts published in `priv/prompts/`. Bill text
history (`docs/superpowers/plans/2026-10-25-bill-text-history.md`): each section
shows where it came from, the steps and reps' part, and an AI change explanation. Search and person pages (`docs/superpowers/plans/2026-10-25-search-and-person-pages.md`): a search box on every page for bills by name, number or text and for people and places, and a page for every person. M1 (schema +
federal adapter) and M2 (your reps, bill pages, accounts with email link and
passkeys, following, daily email) are done and in production.

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
