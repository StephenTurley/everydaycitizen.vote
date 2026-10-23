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

## 2026-10-23 — Federal rate limiters live in an adapter supervisor
`TheFloor.Adapters.Federal.Supervisor` starts the named limiters (intervals from `:federal_rate_limits`); `application.ex` only lists it, and `Ingest.RateLimiter` stays generic. Keeps the jurisdiction boundary intact.

## 2026-10-23 — Bill child sets are replaced wholesale; actions keyed by (bill, position)
`BillActions` and `Sponsorships` upsert the incoming rows and delete the bill's others in one transaction, so source corrections and withdrawn entries disappear. Actions use `(bill_id, position)` as natural key; sponsorships `(bill, person, classification)`. Bill-scoped records carry `jurisdiction` because external bill ids are only unique per jurisdiction.

## 2026-10-23 — Bill version text has its own provenance column
`bill_versions.text_source_id` records where the text came from, separate from `source_id` (version metadata); re-ingesting metadata never clears stored text.

## 2026-10-23 — Votes keep unknown people; events keep unresolved bill labels and raw status
`vote_positions.person_id` is nullable: positions for people not yet ingested are saved with `raw_label` rather than failing the vote, and a vote's positions are replaced as a set (delete then insert in one transaction). A vote with an unknown bill saves `bill_id: nil`; an unknown body or session is an error. Events link resolved bills through `event_bills` (replaced as a set) and store everything unresolved (adapter raw labels plus ids not found) in `unresolved_bill_labels`. `events.status` keeps the raw source status so cancelled events retain their row.

## 2026-10-23 — Federal session = congress; sub-sessions for vote numbering
A federal legislative session is the congress (`119`); each congressional session is a child session (`119-1`, `119-2`) because roll-call numbering restarts per session. Sub-session dates are the earliest start / latest end across chambers; the congress is open-ended while any session is. Every list-level job runs inside `Federal.Job.run/2`, which records the ingest run and never advances the cursor on failure.

## 2026-10-23 — Members and committees from unitedstates/congress-legislators
Members and committees come from the `congress-legislators` JSON files (the only source carrying the LIS ids needed to match Senate votes). The historical file is filtered to legislators with a term ending on/after the session start. Committee memberships have nil dates (source lists current members only) and use the committees file as their source ref; unknown people are skipped and counted rather than failing the run.

## 2026-10-23 — Correction: committee memberships use their own source ref
Supersedes the provenance line in the members/committees entry above: `Normalize.Committees.records/4` takes separate committee and membership sources, so committee membership rows point at `committee-membership-current.json` and bodies at `committees-current.json`.

## 2026-10-23 — Bill text from GovInfo package `/xml/`, schema detected from the document
Verified live: `govinfo.gov/content/pkg/BILLS-119hr22ih/uslm/...xml` does not exist (GovInfo answers 200 with an HTML error page, so a 404 fallback never fires). The real file is `.../content/pkg/BILLS-<congress><type><number><code>/xml/BILLS-....xml` (`application/xml`), and for the 119th Congress it is the legacy bill DTD, not USLM. `SyncBillText` therefore fetches that URL, falls back to the version's Congress.gov `xml_url` on 404, and sets `xml_schema` from the root namespace (`uslm` only if a USLM namespace is declared, else `other`). Missing or malformed XML leaves text nil and the job succeeds; 5xx/timeouts are returned for Oban retry. `versions_missing_text/1` now keys on `text_source_id`.

## 2026-10-23 — Senate votes: LIS-keyed positions, shared BillId helper, Eastern-time dates via Tz
Senate roll calls are parsed from senate.gov XML with `Saxy.SimpleForm`; positions are keyed by LIS id (`{"lis", id}`), `Guilty`/`Not Guilty` map to yea/nay and `Not Voting` to absent, and the vote bill is set only when `document_type`/`document_number` form a bill label (nominations `PN` give nil). Vote times are Eastern wall-clock text, converted to UTC with the `tz` time zone database (added as a dependency). `Federal.BillId` is the single builder/parser of bill external ids, identifiers, classifications and display labels. The list job enqueues rolls not stored plus the 10 highest roll numbers because the menu has no update dates. Fixtures are synthetic: senate.gov's WAF returned 403 to every client during capture.

## 2026-10-23 — Bill ingest: per-endpoint sets, 0-based action positions, chamber-only actors
`SyncBills` lists bills updated since the last succeeded run and enqueues one `SyncBill` per bill (unique on congress/type/number for an hour). `SyncBill` makes five requests and writes each record with the source of the response it came from. Actions and sponsorships replace the stored set, so they are written only after a successful fetch of that endpoint; a failed request fails the job for retry, and an empty actions list is not written. Action `position` is 0-based, oldest first (Congress.gov lists newest first). `actor_body_external_id` is only `house`, `senate` or nil, taken from the action's `sourceSystem` (Library of Congress system actions have no chamber). Version `code` is the GovInfo package suffix parsed from the version's format URL; bill `subjects` are the legislative subjects only (the policy area is not included).
