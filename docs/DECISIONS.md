# Decision log

Append-only. One entry per decision: date, decision, one-line rationale.
Newest at the bottom.

## 2026-10-18 — Scope: read-only "educate constituents" tool first
Verified-identity features (debate, proposals, delivery to reps) are deferred.
The read-only product has to be excellent either way and earns the audience
that would make verification worth paying for.

## 2026-10-18 — Federal first, jurisdiction-agnostic schema
Federal data is the cleanest (Congress.gov API, GovInfo, OLRC XML). The
schema follows Open Civic Data conventions so Plural Open (Open States) and
local sources plug in later as adapters with no UI changes.

## 2026-10-18 — "Why" is always attributed, never synthesized
The platform does not explain motives in its own voice. Bias defense is
transparency and contestability (published prompts, side-by-side sources,
report-an-inaccuracy queue), not a claim of neutrality.

## 2026-10-23 — Stack: Elixir + Phoenix LiveView
Server-rendered views over a changing dataset, with alerts and follows mapping
naturally onto PubSub. Ecto + PostgreSQL, Oban for ingest jobs, Req for HTTP,
Saxy for streaming XML.

## 2026-10-23 — Name: The Floor; domain thefloor.vote (Namecheap)
"What's on the floor this week" is the home-page view. Registered at Namecheap.
Note: Namecheap's `.vote` renewal is ~$134/yr vs ~$81 at Porkbun; consider
transferring after the 60-day registration lock. DNS not yet configured.

## 2026-10-23 — Toolchain: Erlang 29.0.6 / Elixir 1.20.4-otp-29 via asdf
Pinned in `.tool-versions`. OTP 29 instead of the originally noted OTP 28
because it is what is installed locally and Elixir 1.20 supports it; no Node
pin since Phoenix 1.8 uses standalone esbuild/tailwind binaries.

## 2026-10-23 — Provenance as a `sources` table referenced by every row
Every domain row points at a `sources` row (url, fetched_at, last_seen_at,
content_hash) deduplicated on (url, content_hash); re-fetching identical bytes
only advances `last_seen_at`. Keeps provenance non-null without duplicating it.

## 2026-10-23 — Oban for ingest
Scheduled, incremental, idempotent ingest jobs run as Oban workers (queues
`ingest` and `text`), with each execution recorded in `ingest_runs`.

## 2026-10-23 — CodeSection deferred to M4 (redline)
The current-law CodeSection entity is only the redline target, so it is not
needed for M1 coverage checks; it lands with the redline engine in M4.

## 2026-10-23 — Memberships unique with NULLS NOT DISTINCT (committee memberships have no dates)
Unique index on (person_id, body_id, role, start_date) uses `NULLS NOT DISTINCT`
(PG >= 15) so undated committee memberships upsert instead of duplicating.
Known limitation: members who leave a committee are not end-dated in M1.
