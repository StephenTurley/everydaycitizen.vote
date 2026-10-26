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

## 2026-10-23 — House votes: members-sourced provenance, candidate votes as present, shared vote helpers
House roll calls come from the Congress.gov `house-vote` detail and `/members` endpoints; the vote's `SourceRef` is the members response (positions dominate). Counts are the `votePartyTotal` entries summed (Speaker-election votes carry per-candidate totals, counted as `present`, and each candidate vote maps to `present` with the raw name kept). `startDate` has an explicit offset so it is converted to UTC directly. The list job enqueues unstored rolls plus rolls whose `updateDate` is at or after the cursor. Result-to-`passed` heuristics and Eastern-time conversion moved to `Federal.VoteSupport`, and session fan-out to `Federal.Sessions`, shared with the Senate jobs.

## 2026-10-23 — Committee calendars from Congress.gov committee-meeting

Committee calendars come from Congress.gov `committee-meeting` (both chambers, typed) instead of docs.house.gov + senate.gov: one primary source, one normalizer. Hearing/Open Hearing/Closed Hearing map to `hearing`, Markup to `markup`, other types (Meeting, Open Business Meeting) to `other` with the raw type kept; source status is stored lowercased and canceled meetings keep their row. Meetings in the next 14 days are re-fetched each run (their chamber is read from the stored source URL).

## 2026-10-23 — Floor schedules: House from docs.house.gov weekly XML, Senate from an unverified page parser
House floor comes from the docs.house.gov weekly XML (`Download.aspx?file=/billsthisweek/YYYYMMDD/YYYYMMDD.xml`, Monday of the current and next week) instead of the Majority Leader HTML page: official, machine-readable, same content. The URL format was confirmed against a real week (20260914, content-type application/x-octet-stream); a week with no published schedule answers HTTP 200 with an HTML page, so HTML-200 and 404 both mean "no events" (`HTTP.html?/1`, shared with bill text). One all-day floor event per top-level floor item; sub-items (reports, prints) are not events; items with a `remove-date` get status `removed`. The Senate page is parsed with LazyHTML by walking dated headings; senate.gov returns 403 to our capture machine, so that parser and its fixture are synthetic and unverified against the live page. Both jobs warn and record `items: 0` when a fetched document yields no events (an absent House week is normal and does not warn). `BillId.scan/2` finds bill labels in free text and is shared by both normalizers.

## 2026-10-23 — Coverage checks: one-sided tolerance, failed fetch is a failed check
A check passes iff `actual <= expected` and `actual >= floor(expected * (1 - tolerance))`: we may lag the source by the tolerance but must never hold more than it reports. Tolerance is 0.005 for bills (introduced during a run) and 0 for votes and members. Votes get one check per stored child session (`votes:house:119-1`, `votes:senate:119-2`); member checks count current members by the chamber of their latest term. If the expected count cannot be fetched (e.g. senate.gov answers 403), the check is stored with `expected` NULL, `passed` false and an `error` note, and `mix the_floor.coverage` shows it as FAIL; the coverage job never crashes on a source failure. Live smoke on 2026-10-23: Congress.gov reported 19,775 bills, 439 current House members, 100 senators, 362 and 314 House votes for sessions 1 and 2; senate.gov returned 403 from the capture machine. The full backfill-then-coverage run (M1 done-when) is left to be run by the user.

## 2026-10-23 — Ingest adapter registry for the mix tasks
Mix tasks are jurisdiction-agnostic: `config :the_floor, :ingest_adapters` lists modules whose `all/0` returns ordered `{name, worker, args}`, so `mix the_floor.ingest` never names the federal adapter and the boundary test holds. Tasks start the app with Oban queues and plugins off, so they enqueue (or read) without running jobs or the cron in a VM that exits. The nightly cron runs the vote jobs without a `session` arg (every stored session of the congress, one cheap list request each) rather than only the current session, since cron arguments are static.

## 2026-10-23 — First full ingest: prerequisite snoozes and job priorities
List jobs start together (`ingest` concurrency 4) and finish in any order, so registry order is only a priority hint. Each list job checks the data it needs before `Federal.Job.run/2` and returns `{:snooze, 300}` when it is missing, so no run is recorded and no cursor moves: members need the congress session; bills need the session and ≥1 person; vote lists need ≥1 stored child session and ≥1 person; committee meetings need the session and ≥1 committee body. After 24 snoozes (~2 h) a missing prerequisite becomes `{:error, {:missing_prerequisite, name}}` so Oban retries and then discards it instead of snoozing forever. Detail jobs (SyncBill, SyncBillText, SyncHouseVote, SyncSenateVote, SyncCommitteeMeeting) run at Oban priority 5 and list jobs at 0–3, so list jobs are picked first. `relink` and `coverage` snooze while other ingest-queue jobs are still to run (relink ignores coverage), capped at the same 24 snoozes. Oban Lifeline (rescue after 30 min) and Pruner (7 days) are enabled outside test.

## 2026-10-23 — Vote references kept for relinking
`votes.bill_ref` and `vote_positions.person_scheme`/`person_value` store the source's references on every write, whether or not the bill or person is stored yet. `TheFloor.Ingest.Relink.run/0` (jurisdiction-agnostic) fills a nil `bill_id` from `bill_ref` within the vote body's jurisdiction and a nil `person_id` from `person_identifiers`; the federal `relink` job runs it after the list jobs, before coverage, and nightly at 05:30 America/New_York. A vote with no body is now `{:error, {:unknown_body, nil}}`.

## 2026-10-23 — Incremental listings overlap the cursor by 2 days
`SyncBills` and `SyncCommitteeMeetings` list from `fromDateTime = cursor − 2 days`, so an item whose detail job was discarded after its attempts, or that offset paging over a shifting `updateDate` skipped, is listed again on the next run. Writers are idempotent and `SyncBill` is unique per bill for an hour, so the overlap costs only repeat detail fetches. Coverage records one failed `votes:<chamber>` check ("no child sessions stored") when the congress has no stored child sessions.

## 2026-10-23 — Hosting on Fly.io with CI-gated deploys
Fly.io app `thefloor-vote` in `iad` (the name `the-floor` was taken) with an unmanaged single-node Fly Postgres (`thefloor-vote-db`, shared-cpu-1x, 1 GB volume), the cheapest Postgres Fly offers. One 512 MB shared machine with auto-stop off and `min_machines_running = 1`, because Oban Cron runs the nightly ingest inside the app; deploys use `--ha=false` to keep it at one machine. GitHub Actions runs format, credo `--strict`, warnings-as-errors and tests against Postgres 17 on every push and PR, and deploys `main` only after they pass. The release image adds `cmake` (lazy_html has no precompiled NIF for OTP 29) and downloads Tailwind with curl, since its `:httpc` installer rejects GitHub's long redirect headers. Ingest helpers moved out of the Mix-only module (`TheFloor.Ingest.Jobs`, `Coverage.format_rows/1`) so `TheFloor.Release.ingest/1` and `coverage/0` work in a release via `bin/the_floor rpc`.

## 2026-10-23 — First bill and text ingest from GovInfo bulk data
The first `sync_bills` run (no cursor) reads GovInfo's BILLSTATUS bulk zips (one per bill type) instead of ~6 Congress.gov requests per bill, which took ~25 h at the API's 5,000 requests/hour. BILLSTATUS is the official source the API is built from and uses its field names, so `Normalize.BillStatus` converts each file to the API's response shape and the same `Normalize.Bill` + `BillWriter` path writes both; a parity test pins identical records for 119 H.R. 22 (text-version links point at GovInfo instead of congress.gov). Each record's provenance is its own per-file bulkdata URL, the zip's download time and the hash of the entry's bytes, which equals the hash of that URL's body (checked live). The run is recorded as `sync_bills`, so later runs list from the API with the usual 2-day overlap, which covers the hours bulk files lag the API. A missing zip is skipped, a zip that fails otherwise fails the run, and a run that writes no bills fails so no cursor is set over an empty database; an unreadable entry falls back to a `SyncBill` job. The run then enqueues `BackfillBillText`, which fills version text from the BILLS zips (one per session and type) and falls back to `SyncBillText` for every version still missing text. Bills now wait for a succeeded `sync_members` run, so sponsorships are not dropped while members are still being written.

## 2026-10-23 — Actions may have no description
`bill_actions.description` is nullable. Congress.gov and BILLSTATUS both carry some Library of Congress actions with only a date and a code (e.g. `Intro-S`); requiring a description made 29 of 19,769 live 119th-Congress bills unwritable by either path. They are stored as the source gives them and flagged unclassified, never given invented text.

## 2026-10-23 — Bulk jobs time out before Lifeline rescues them
Oban Lifeline makes a job still `executing` after `rescue_after` runnable again even if it is still running, so `rescue_after` is 2 h and the bulk `SyncBills` and `BackfillBillText` workers time out at 90 min (a test pins timeout < rescue_after). One unreadable, unparseable or failing bulk entry, raised or returned, falls back to its per-item API job instead of failing the run, so a single bad file cannot block the first ingest.

## 2026-10-23 — Sentry for errors and nightly-job monitoring
Sentry (org `thefloorvote`, project `the-floor`, SDK `sentry ~> 14.0`), set up like turley.dev: request errors via `Sentry.PlugCapture`, crashes via the SDK's logger handler (no log messages), failed Oban jobs as issues (a transient source failure, i.e. transport error, 429 or 5xx, only on its last attempt), and every Oban Cron job on Sentry's Crons page so a nightly ingest that fails, overruns or never starts is visible. Reports carry no request bodies, cookies or query strings, since M2's rep lookup takes a visitor's address. Releases are `the-floor@<git sha>` from the deploy's image label. Tracing and a browser project are left until there is a UI to measure. `SENTRY_DSN` is optional; nothing is sent without it.

## 2026-10-23 — Canonical host thefloor.vote
The app answers on `thefloor.vote` (A/AAAA to the Fly app's IPs, Fly-issued certificate); `www.thefloor.vote` and `thefloor-vote.fly.dev` redirect (301) to it via `TheFloorWeb.CanonicalHost`, which reads the host from `PHX_HOST`, because LiveView sockets only accept the configured origin.

## 2026-10-23 — Senate roll-call votes from Voteview
senate.gov answers every automated client with 403 (Akamai bot protection; tried from the dev machine and Fly with browser headers), and Congress.gov has no Senate vote endpoint, so Senate votes come from Voteview (UCLA), an exception to the primary-source rule until a better source exists. Voteview publishes no terms or rate limits; to stay a light, identifiable client we fetch only its documented bulk files (`static/data/out/{rollcalls,votes,members}/S{congress}_*.csv`), three requests per run through a 2 s `voteview` limiter with our User-Agent, never the per-vote `api/download` endpoint the site uses internally. Provenance is per file: each vote's source is the votes CSV (URL, fetch time, hash). Votes keep the Senate's numbering (`clerk_rollnumber` per session) and are matched by bioguide id; only Senate members' rows count (the file also carries the President's announced positions), and a tie that passed gets the Vice President's yea added to the totals. A new `votes:senate:tallies` check holds Voteview to an official source: every tally printed in a Senate bill action ("52 - 48. Record Vote Number: 123") must match the stored totals (all 277 matched on 2026-10-23). Voteview asks to be cited: Lewis, Jeffrey B., Keith Poole, Howard Rosenthal, Adam Boche, Aaron Rudkin, and Luke Sonnet. Voteview: Congressional Roll-Call Votes Database. https://voteview.com/. The Senate floor schedule stays on senate.gov and fails visibly until M2 picks a source.

## 2026-10-24 — Bulk loads run as small chunk jobs
On Fly the first bill load wrote ~200 bills a minute (shared CPUs), so one job for all 19,740 bills could never finish inside its 90-minute timeout, and each retry started over. The first `sync_bills` run is now a coordinator (`Federal.BulkBatch`): it counts each BILLSTATUS zip, queues one `BulkBillsChunk` job per 1,000 entries on a new `bulk` queue (concurrency 4), and snoozes until they finish; only then does it record `sync_bills` (so the cursor means a complete load) and queue the text backfill, which is split the same way (`BulkBillTextChunk`, with the per-version fallback once all chunks finish). A batch is an ingest run (`bulk_bills`, `bulk_bill_text`) left `running` while its chunks work, so a retry or the next night's run joins it instead of starting another. Chunks skip bills already stored with the same source update time and versions already holding text, so a retried chunk does only what is left; each bill's parts are written in one transaction (`Ingest.atomically/1`) so a killed chunk never leaves a bill without its actions. A discarded bill chunk fails the batch and the next run starts a new one (cheap, everything done is skipped).

## 2026-10-24 — Production sizing for the first backfill
The app machine is 1 GB (512 MB was killed decoding `legislators-historical.json`). The Postgres machine runs on `performance-1x` / 2 GB only for the first backfill (a trivial query took 36 ms on throttled `shared-cpu-1x`), then returns to `shared-cpu-1x` / 1 GB.

## 2026-10-24 — Official bill summaries stored, attributed and sanitized
`bill_summaries` holds each bill's official summaries (one row per version code and action date), with an `author` the adapter sets ("Congressional Research Service" for federal), so the UI labels a summary by its author without knowing the jurisdiction. Summary HTML is reduced on write to `p ul ol li strong em b i br` without attributes (`TheFloor.Ingest.SafeHtml`), so it can be rendered as HTML safely. The API path fetches `/summaries` per bill; the bulk path reads them from BILLSTATUS. Bills stored before this are filled by the on-demand `bill_summaries` job (bulk chunks in summaries-only mode). On-demand jobs (`Jobs.on_demand/0`) run only by name, never in the full ingest.

## 2026-10-24 — Votes carry a normalized type
`votes.classification` is one of `passage cloture amendment nomination procedural other`, set by the adapter from the roll call's question (`Federal.VoteClassifier`; procedural motions are matched before amendments, so tabling an amendment is procedural). Pages use it to pick a bill's main vote per chamber (passage there, else the latest roll call). Stored votes are retyped by the on-demand `reclassify_votes` job.

## 2026-10-24 — Bill text stored split into sections
`bill_versions.sections` (JSON) holds each version's text as titles and sections, each section's text flattened into indented blocks (level 0 section text and subsections, 1 paragraphs, down to 5 items), parsed from the stored XML (bill DTD or USLM) when text is stored. Sections quoted into existing law (`<quoted-block>`) stay inline in the quoting block. The bill page renders sections from it, and M3 summaries will attach per section. Versions stored earlier are split by the on-demand `bill_sections` job (500 per run, re-queueing itself); unparseable XML gets `[]`. Live check: 2,000 random stored versions, 0 errors, ~2.6 ms each.

## 2026-10-24 — Finding reps from an address
`TheFloor.Reps` finds a place's current members through a per-jurisdiction `TheFloor.Reps.Locator` (`config :the_floor, :locators`); the federal one is the Census Geocoder, using the geography vintage that holds the sitting congress's districts (`census_vintages: %{119 => "ACS2025_Current"}`), because the current vintage already carries the next congress's districts and several states redrew mid-decade. A locator returns a district key (`"IA-1"`, `"DC-AL"`) and its seats (`{"senate","IA"}`, `{"house","IA-1"}`); pages and the session keep only the key, never the address. Places without senators simply match none.

## 2026-10-24 — Find your reps by ZIP code first
The home page asks for a ZIP code before an address. `postal_districts` maps postal codes to district keys with each one's share of the postal area's land, loaded for federal from Census's 119th-Congress district-to-ZCTA relationship file by the on-demand `zip_districts` job (re-run once per congress). A ZIP code in one district goes straight to its reps (82.6% of the 33,791 ZIP areas; fewer by population, since city ZIPs split more often); a split ZIP asks for the street and geocodes it with the ZIP; an unknown ZIP (PO boxes, single-building ZIPs) falls back to the full address. ZIP areas (ZCTAs) approximate USPS ZIPs; a district that only grazes a ZIP area makes it "split", which errs toward asking for the street. ZIP codes are handled like addresses: never stored, logged (`filter_parameters`) or put in a URL. Chosen over third-party address autocomplete, which would send each keystroke to another company.

## 2026-10-24 — One Sentry cron monitor, on the coverage job
Sentry's free plan allows one cron monitor, and the Oban integration's cron reporting created one per scheduled worker (10), so all but the first were dropped. Its cron reporting is off; `TheFloor.SentryCrons.monitor/2` reports only the coverage job's scheduled runs. Coverage runs last each night after the other ingest jobs settle, so an on-time "ok" means the scheduler and app ran the night; individual job failures still arrive as Sentry issues.

## 2026-10-24 — Quoted law keeps its structure; split format versioned
Language a bill inserts into existing law (`<quoted-block>`, USLM `<quotedContent>`) was flattened into one paragraph with its numbers and headings run together (about a quarter of stored versions). The section splitter now keeps it as a `"quote"` block holding its own levelled blocks, rendered as a set-off block labeled "Text this section adds to the law". `bill_versions.sections_version` records the splitter's output format (`BillSections.format/0`, now 2); the on-demand `bill_sections` job re-splits any version on an older or unrecorded format, 100 per job, so pages keep the old split until each version is redone rather than showing no text.

## 2026-10-24 — Desktop bill page
From 1024px the bill page widens to a 1280px column: the bill text (720px max, Source Serif 4 at 17px) beside a sticky sidebar with where it stands (as a vertical list), your reps and votes; from 1280px a contents list of the bill's sections sits on the left. Expand all / Collapse all is `?section=all`. Phones keep the approved single column. A status step reached with no date of its own (a bill that went to the floor without a committee report) reads "Skipped".

## 2026-10-24 — Desktop layouts for home, your reps and this week
From 1024px every page's header spans the same 1280px column. Your reps puts the reps in a left column (300px, the selected one marked with `aria-current`) beside a 720px feed; This week puts the days in a 720px column beside a sidebar with previous/next week links and the Everything / My reps switch, which now says what My reps includes; Home sets the ZIP finder beside three short cards on what the site shows. Phones keep the single column; This week gains the week links there too. UI copy names no legislature ("This week's schedule"), so the pages stay jurisdiction-neutral.

## 2026-10-24 — Renamed to Everyday Citizen (everydaycitizen.vote)
Before launch and before email and passkeys tie the product to a domain, the site is renamed from The Floor to Everyday Citizen, at `everydaycitizen.vote`. The site exists so that being an engaged citizen is simple for people who are not engaged now, first by explaining what their reps do in plain language, later by letting them second proposals and send them to their reps; "everyday" says it is for ordinary people, not insiders. Names were checked against the web and trademark aggregators first: "The Floor" overlaps thefloorhq.com, and "Good Citizen" a civics-education nonprofit (goodcitizen.org); no civic product uses "Everyday Citizen" (the only mark found is for apparel). User-facing text changes; code, Fly and Sentry names keep `the_floor`/`thefloor-vote`. The old domain needs no redirect (no users yet); the canonical-host redirect sends it to the new host while its certificate lasts.

## 2026-10-24 — Accounts without passwords; the district on the account
Accounts come from `phx.gen.auth` (magic link) with passwords removed: one sign-in page sends an emailed link and creates an unconfirmed account for an unknown email (the reply is the same either way), or signs in with a passkey. The account holds the email, a district key (never an address) and daily email settings. The district carries across sign-in: one looked up before signing in is saved on an account without one; an account's is used when the session has none; a new lookup while signed in replaces it. Only changing the email needs a recent sign-in.

## 2026-10-24 — Passkeys
Passkeys follow turley.dev on `wax_`: a `user_keys` table, `PasskeyLogin`/`PasskeyRegister` LiveView hooks, a 60-second single-use token handing a verified passkey sign-in to the session controller, and sessions tied to the passkey that started them so removing it ends them. The relying party is `everydaycitizen.vote` (origin `https://everydaycitizen.vote`); it can never change once passkeys exist. The WebAuthn user handle is the account id, never the email.

## 2026-10-24 — Following and the daily email
A `follows` row is a person following a bill or a rep (exactly one, once). The daily email runs at 07:00 America/New_York: one unique job per person and day for confirmed accounts with the email on who follow something. It lists rows first stored (`inserted_at`) after the person's `digest_sent_at` cutoff up to the run's scheduled time (votes key on the vote row, since positions are rewritten on every fetch): new actions, text versions and roll calls on followed bills; a followed rep's votes, introductions and movement on their bills. Nothing new sends nothing; the cutoff moves only after a successful send, so failures retry and missed days catch up. Mail goes through Resend (`RESEND_API_KEY`, required in production); unsubscribe is a signed link (GET asks, POST and RFC 8058 one-click turn it off).

## 2026-10-24 — Deploys release the jobs they interrupt; bills link their official page
Oban's node name is per machine and deploy image in production, and at boot `TheFloor.ObanRescue` makes jobs left executing by another node available again (Lifeline's two-hour window stays for genuinely long jobs). Bills store `web_url`, their page for people (Congress.gov for federal, built by the adapter; a backfill job `bill_web_urls` fills existing bills), which the bill page links as "Official page".

## 2026-10-24 — Code and repo renamed to Everyday Citizen
The Elixir app is now `everyday_citizen` (modules `EverydayCitizen`, `EverydayCitizenWeb`, release `/app/bin/everyday_citizen`, Mix tasks `mix everyday_citizen.*`) and the GitHub repo `StephenTurley/everydaycitizen.vote`, so the code carries the product's name before there are users (the session cookies changed name, signing everyone out). A migration rewrites the worker names of unfinished Oban jobs. Kept on purpose: the Fly app `thefloor-vote` (Fly cannot rename apps; changing means a new app and database move), the Sentry org/project and the coverage cron monitor's slug (the free plan allows one monitor, so `Coverage` passes the existing slug), the local `the_floor_dev`/`the_floor_test` database names, and historical docs.

## 2026-10-24 — Blue-green deploys; jobs of stopped nodes released by heartbeat
Deploys use Fly's blue-green strategy, as turley.dev does: health checks `/health` (liveness, no database) and `/health/ready` (database answers), checked before traffic moves; `kill_timeout` 60 s and Oban's 25 s shutdown grace. Every deploy now gets a new machine, so the boot-time rescue of the same machine's earlier jobs no longer applies: each node records a heartbeat every 30 s, and a sweep every minute releases jobs executing on nodes silent for 2 minutes. Migrations must work with both the old and new code (docs/ops/deploys.md).

## 2026-10-24 — M3 as built: plain-English summaries on view, cached
At the owner's direction the plain-language layer is one LLM summary per bill section, in plain English a high school student could follow, written the first time someone opens that section and cached (`section_summaries`, keyed by version, section index and prompt version, shown only while the section's text still hashes to what was summarized). Claude Haiku via the Messages API, temperature 0, 400-token replies; the prompt is published at `priv/prompts/section_summary.v1.md` and forbids opinions, reasons, predictions and anything not in the text, treating the section as data. Cost guards: no bulk processing ("Expand all" shows cached summaries only), 300 new summaries a day site-wide, 30 requests an hour per visitor, sections over 40,000 characters skipped, one job per section at a time. Summaries appear on any bill a person opens, replacing the spec's movement filter (CLAUDE.md updated). Not yet built from SPEC §7.6: the second independent model with disagreement flags and the "report an inaccuracy" queue.

## 2026-10-24 — Claude credentials by Workload Identity Federation
The owner's Anthropic API keys expire every 30 days, so production does not depend on a stored key: the machine gets a signed OIDC token from Fly (issuer `https://oidc.fly.io/personal`, subject `personal:thefloor-vote:<machine>`) and exchanges it at Anthropic's `/v1/oauth/token` for a short-lived access token, cached and renewed two minutes before expiry (`EverydayCitizen.Summaries.Credentials`). The federation rule, service account, organization and workspace IDs are configuration, not secrets. `ANTHROPIC_API_KEY` remains for development, and in production only until federation is set up.

## 2026-10-24 — Correction: no temperature on summary requests
Claude Haiku 5.5 rejects `temperature` (deprecated for the model), so summary requests send none; the entry above that says "temperature 0" is superseded. Steadiness comes from the published prompt.

## 2026-10-24 — M3b: bill and week summaries, a dollar budget
At the owner's direction there are now three AI summaries, each with its own published prompt (`priv/prompts/`): a shorter section summary (v2: at most 3 sentences or 4 bullets, clerical changes left out); an executive summary of every bill above its text, from the newest version's full text, its length scaled to the bill's size (bands short/medium/long/very long, passed to the model); and on the reps page a summary of what the selected rep did on the record in the week being viewed. Bill and week summaries share one table, `ai_summaries` (kind, subject, prompt version), shown only while their input still hashes to what was summarized, so new bill text or a new vote in the week writes a fresh one on the next view. A bill over 250,000 characters is split at section breaks into parts of at most that size (each under the model's long-prompt price tier), each part summarized, then combined in one final call. The count-based daily limit is replaced by a dollar budget: every call records its tokens and cost in `ai_usage` at the configured rates, and new summaries pause once today's spend reaches $2 (checked before every call, so a huge bill cannot run far past it). The reps page opens on the rep's most recent active week, not always the current one, so a recess does not open on an empty page.

## 2026-10-24 — Correction: summary requests turn thinking off
Claude Haiku 5.5 thinks before answering by default, and on a whole bill it spent the entire 500-token reply cap thinking and returned no text, so bill summaries failed in production. Summary requests now send `thinking: {type: "disabled"}`; the published prompts already say what to write, and the reply caps stay as set.

## 2026-10-24 — Crawlers never start a summary
Pages fetched by crawlers, link previewers and scripts (by user agent: bot, crawl, spider, preview, headless browsers, curl, HTTP libraries; `EverydayCitizenWeb.Crawler`) show summaries already written but never queue new ones, for sections, whole bills and rep weeks; with nothing cached the summary box is left out. Pages stay indexable (robots.txt unchanged). Clients that pass as browsers remain bounded by the daily budget and the per-visitor limit.

## 2026-10-24 — Bill summaries in four parts, with a made-up example
At the owner's direction (a summary that stated a deduction cap without making it understandable), the bill summary prompt v2 writes four parts: the summary; "Who this affects" (each group the bill applies to and what changes for it, as the bill states, including both sides when it gives one group something and requires something of another); "Words to know" (definitions only); and "For example" — made-up numbers with the arithmetic shown when the bill has amounts, limits or multiples, else a made-up situation. The example applies only the bill's own rules: no outside facts such as tax rates or prices, no further effects, no names or demographics, the case the bill most plainly addresses. The page shows each part under its heading and sets the example apart. Reply caps rise to 600/800/1,200/1,700 tokens by length band; the part prompt (v2) keeps exact numbers and who each rule applies to so very long bills can have examples. "Who benefits" stays out of the product's voice; attributed context (CBO, committee reports) is M5.

## 2026-10-24 — Bill summaries are never kept cut off
The first v2 summary in production ran into its 800-token cap before reaching "For example", and the cut-off reply was stored. Now a bill summary that stops at its cap is asked for once more with twice the room; if that is cut off too, nothing is stored and the page says a summary is unavailable (the job does not retry, since another attempt would pay for the same). Caps rise to 900/1,200/1,600/2,000 by length band, and prompt v3 says the length band limits only the first part, strictly, and that all four parts are always written.

## 2026-10-24 — Feedback: report a problem, one email per report
Every AI summary (section, bill, week) has "Report a problem" (a reason — inaccurate, unclear, missing something, one-sided, other — and an optional note up to 1,000 characters), and every page's footer links to a site feedback form. No login; a signed-in reporter's account is linked. Each report is stored in `feedback_reports` with what the reader was shown (summary text, subject, prompt version, page) and emailed to `FEEDBACK_EMAIL`, one email per report; there is no resolve workflow or status for reporters (owner, 2026-10-24). No IP or address is stored; five reports an hour per visitor, and a hidden field drops bots.

## 2026-10-24 — Emails carry a formatted version and a Reply-To
Sign-in, confirmation and email-change emails now send a formatted (HTML) version beside the plain text, as the daily email already did; filters treat multipart mail as more legitimate. Every email to readers carries a Reply-To (`MAIL_REPLY_TO`), since hello@ only forwards; feedback emails reply to the reporter when signed in. Authentication (DKIM, SPF on the sending subdomain, DMARC p=none) was checked and is in place; junk placement at iCloud is otherwise a new-domain reputation matter.

## 2026-10-24 — Senate floor schedule from the Congressional Record
senate.gov answers every automated request with 403 (a bot firewall), so the Senate's floor schedule now comes from the Congressional Record: for the latest three daily issues (Congress.gov API), the Daily Digest's "Next Meeting of the SENATE" article gives the meeting's time and date and its "Program for <day>" text, written as one floor event per meeting date. It is official and neutral but posts the morning after each session day, so it is about a day behind the chamber's own schedule; the job runs at 03:00, 12:00 and 18:00 Eastern. The Senate Democratic Caucus feed, the only source found that posts the next day's schedule ahead, was not used: a party's site. The senate.gov page parser and its rate limiter are removed; Senate votes still come from Voteview.

## 2026-10-24 — Votes say what they were on
Votes keep the source's description of what was voted on (`description`: a nominee, an amendment's purpose or label) and, when it is not the bill, its reference and official page (`subject_ref`, `subject_url`). Half the Senate's roll calls (nominations and cloture on them) had no bill and showed only "On the Nomination"; they now show the nominee. House amendment votes link the amendment's official page. Senate nomination references are kept but not linked: Voteview runs the part number onto them (PN9991 is PN999, part 1), so a link is made only once checked against the official record (next step). Procedural questions (cloture, motions to proceed, table, discharge, nominations) carry a folded plain definition: what the procedure is, never why it is used.

## 2026-10-24 — Senate votes link the nomination or amendment they were on
A nightly job (`vote_subjects`, after the Senate votes) links Senate votes without a page to their official Congress.gov record. Nominations: Voteview runs part numbers onto references (PN9991 is PN999, part 1), so each split of the digits is looked up in the Congress.gov nomination list and taken only when the record's nominee name matches the vote's description; no match means no link, never a guess (about 94% of the 119th Congress's nomination votes link; Voteview's own mix-ups stay unlinked). Amendments: a bill's amendment list gives each amendment's deciding "Record Vote Number", matched to the vote's session and roll (all 104 Senate amendment votes in the 119th). Only the vote's subject reference and page change (`Records.VoteSubject`).

## 2026-10-25 — Bill text history ("git blame for law")
At the owner's direction (H.R. 7008's voter photo ID section arrived in a Rules Committee substitute "considered adopted" under a rule, with no separate vote, and nothing on the page showed it), every section of a bill's text now says where it came from: since introduced, changed (when), or added (when). An opened changed or added section shows the steps that touched it — each version's window of committee steps, agreed amendments with their official description and page, and roll calls on the bill and on its procedurally related measures (the rule) — the reader's reps' votes in those steps and membership of a committee that acted, the change marked clause by clause, and an AI explanation of what the change does (prompt `change_summary.v1.md`, on view, cached, budgeted, never why). Bills now store committee activity, related measures (`procedural` or `related`) and amendments (detail fetched only for agreed amendments without a description); `bill_history` re-syncs bills with two or more versions. Lineage is computed from stored version sections, matched by heading, compared clause by clause at the text's own numbering since versions split paragraphs differently. Committee members' markup votes are not in the sources, and the page says so.

## 2026-10-25 — Tests never reach outside services
Every HTTP request goes through a Req.Test plug in tests and mail through Swoosh's test adapter; `NoNetworkTest` fails if app code makes a request without one of the stubbable settings (owner's rule).

## 2026-10-25 — Bills keep every title they go by
A bill is searched by the names people use, and the single stored title misses most of them, so `bill_titles` holds each title with its kind (`official`, `short`, `popular`, and `part` for the titles of a bill's parts) and the usual provenance; the title the bill page shows is unchanged. The nightly bill sync fetches titles, and a one-off backfill fills the stored bills. The backfill runs one at a time on its own `backfill` queue so the nightly jobs keep their request budget, and a re-run enqueues only bills with no titles yet, so it resumes rather than doubling the load (Oban's unique option is ignored by `insert_all`).

## 2026-10-25 — One rule for comparing names
Title and person-name matching all go through the database function `ec_name_key` (case, punctuation, a trailing "Act" or "of <year>" ignored), so the search, its indexes and its ranking agree on what "the same name" means and a rule change is made in one place.

## 2026-10-25 — Bill text is searched with an expression index, latest version picked at query time
A full-text GIN expression index over `bill_versions.plain_text` adds no duplicate column (production has about 2 GB free and goes read-only near full) and needs no maintenance as versions arrive; the query picks each bill's latest version that has text. Quoted phrases match all their words rather than the exact phrase (a phrase query measured 6.2 s on a public endpoint), and text searches time out at 3 seconds. The match set is capped at 1,000 before ranking, ordered so the cap keeps the furthest-along bills (became law, passed a chamber, roll call, reported, introduced).

## 2026-10-25 — Places and district labels come from the locator adapter
Search must know that "Ohio" or a postal code names a place and how to label a district, without the domain knowing which legislature it is, so both are callbacks on `Reps.Locator`, implemented by the adapter beside the geocoder. When a query names a place, that place's members are listed first, ahead of bill matches (a text search for "iowa" otherwise buried the state's members under about 270 bills).

## 2026-10-25 — Search is a POST, and addresses never reach the URL
Addresses and ZIP codes are never stored, logged or put in URLs, so the search box posts, classifies the query (erring toward treating it as an address), and sends addresses to the reps flow without keeping them; the results page for ordinary queries is a shareable `/search?q=`. A hand-typed address in the URL is cleared from it by redirecting to `/search` with no query, and the Sentry referer header drops its query string. The box is hidden on mail-link pages (unsubscribe), which are reached from email and have no CSRF-protected pipeline; adding one was not worth a search box there.

## 2026-10-25 — People are at /people/:id on internal ids
The database is never rebuilt, so internal ids are stable, and the page then shows no external ids, which keeps the page free of source-specific identifiers. Person pages are indexed.

## 2026-10-25 — Search pages are noindex
Result pages are endless combinations of queries with thin content; they stay out of search engines while bill and person pages remain indexable.

## 2026-10-25 — Search: stricter address rule, a search limit, and crash reports without page state
Found in the final review. Any query starting with a street number that contains a street word anywhere is an address ("1 way forward" included, erring toward address as the spec says). So are a ZIP or 9-digit ZIP+4 anywhere in a query, PO Box spellings, and a five-digit "bill number" no stored bill has (a state and ZIP such as "IA 50309"); Unicode spaces are normalized first. Searches are limited to 60 a minute per visitor; a search runs once the page is connected, so the visitor's IP is known. Sentry's `before_send` drops a crashing process's state and last message and strips query strings from URLs, so a LiveView crash can't carry a search. `<details>` keep their open state across LiveView updates. A query of only excluded words ("-tax") is not searched, since it can't use the index. The release command may run for 30 minutes so the text index can build.

## 2026-10-25 — Home page: summaries matched by subject, a partial index for new laws
The home page shows a law's cached plain-English summary by kind, subject (which names the bill version) and prompt version, without reading or re-hashing the bill's text, and does no summary work before the live connection; a partial index on `bill_actions (bill_id, date) WHERE classification = 'became_law'` serves the new-laws list.

## 2026-10-25 — The container starts as root only to open Fly's Machine API socket
Federated sign-in to Claude failed with EACCES: the app runs as `nobody`, and Fly makes `/.fly/api` (the only way a machine gets its OIDC token without a stored secret) root-only. Fly's docs say nothing on non-root access; a community thread suggests giving the app's group write access. The image's entrypoint (`rel/overlays/bin/as_app`) does that and then runs the command as `nobody` via `setpriv`, so the app itself never runs as root. Chosen by the owner over storing a Fly API token or keeping the 30-day Anthropic key.

## 2026-10-25 — Fly's OIDC tokens name the organization, not its `personal` alias
Correction to the federation entry above: Fly issues tokens with issuer `https://oidc.fly.io/stephen-980` and subject `stephen-980:thefloor-vote:<machine>`, using the organization's name, even though the app's org slug is `personal` and `oidc.fly.io/personal` serves its own discovery document. The Claude Console issuer and rule now use `stephen-980`; with `personal` the exchange returned 401.

## 2026-10-26 — Bill summaries lead with "If this becomes law"
Owner's direction: most visitors give a bill a moment, so the first thing shown is what it would do to people, told from each affected group's side. Prompt v4 adds a part of 1 to 4 groups, each "- label: one sentence", written last in the reply (after the summary it distills, keeping the unheaded first part the length rule and echo check rely on) and shown first on the bill page, the home page's new laws and search results; the rest of the summary is folded below. Reply caps rise by 200 tokens per length band (1,100/1,400/1,800/2,200). Every cached bill summary is rewritten on its next view, inside the daily budget. The owner reviewed real v4 output on sample bills before it shipped.

## 2026-10-26 — Bill summaries are written by Sonnet; the daily budget is $4
Sample v4 stories from Haiku often led with a minor or agency-only group (a retirement bill's hardship-withdrawal rule instead of automatic enrollment), so bill summaries use Claude Sonnet 5.5 ($2/$10 per million tokens, about 3–4¢ a summary); every other kind stays on Haiku. The model and the cost rates are now per kind (`models`, `rates` by model in the summaries config). The daily budget rises from $2 to $4 (owner's decision). The story part's sentences are capped at 20 words, and it never names the legislature, which both models did on samples.

## 2026-10-26 — Search finds cached bill summaries by subject, as the home page does
Search used to read each named bill's full text to find its cached summary (up to 20 heavy queries a search). It now finds them by subject in one query, like the home page: a subject names a version, whose text does not change, so the text's hash is not checked. If a version's text were ever re-ingested under the same code, search and the home page could show the older summary until the bill page writes the new one.

## 2026-10-26 — Votes and events keep the legislature's date; clock times show in the reader's zone
A vote has `voted_on` (the legislature's date, always) and `voted_at` only when the source gives a time; an event has `date` and `start_at` only when it has a clock time (replacing `all_day`). Sources that give only a date (Voteview's Senate votes, the House weekly floor schedule, an untimed Senate meeting) were stored as midnight Eastern, which would show the day before to anyone west of it; they now have no time. A day is always the legislature's own, as in the official record the page links to (a late-night vote reads as its legislative date everywhere). Each jurisdiction records its zone (`time_zone`, set by its adapter), so no shared code names a zone. The reader's zone, reported by the browser on connect and kept in a `tz` cookie for the first render, is used for "today" (this week, a rep's week, what's coming up) and for clock times; without one it is the legislature's zone, and only names in the time-zone database are taken. The site's own day (the summary budget, the 07:00 daily email) runs on `config :site_time_zone`, Eastern.
