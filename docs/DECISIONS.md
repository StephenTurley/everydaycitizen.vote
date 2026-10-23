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
