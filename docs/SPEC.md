# Everyday Citizen (everydaycitizen.vote) — v1 Spec

_Renamed from The Floor (thefloor.vote) on 2026-10-24; see DECISIONS._

Last updated: 2026-10-23

## 1. Purpose

Help constituents answer four questions about legislation, in plain language,
with every claim traceable to its source:

1. **What is being voted on** — upcoming floor votes and committee markups.
2. **By whom** — their own representatives, sponsors, committee members, and
   how each voted.
3. **What it changes** — a redline of the bill's effect on current law.
4. **Why** — the arguments for and against, attributed to whoever made them.

Federal first. The data model is jurisdiction-agnostic so state (via Plural
Open / Open States) and local (Legistar, Municode) plug in later as adapters.

## 2. Scope

**In v1 (read-only):** ingest, your-reps, bill pages, calendar, follow/alerts,
plain-language layer, redline engine, why-panel.

**Explicitly deferred:** debate layer, proposals ("pull requests" for law),
constituent-to-representative delivery, coalition report, identity
verification. Section 9 records the design for these so v1 decisions don't
block them. Nothing in v1 requires user identity beyond an email for alerts.

## 3. Product principles

1. Source text is always visible. Plain language is a reading aid, never the
   thing people act on.
2. The platform never explains *why* in its own voice. Attribute every
   argument to its source and show opposing sources side by side.
3. Aim for transparent and contestable, not "unbiased": publish summarization
   prompts, flag model disagreement, and offer "report an inaccuracy" with a
   review queue.
4. Run expensive layers only on bills with movement (section 6).
5. Prefer official primary sources over aggregators.

## 4. Data model (jurisdiction-agnostic)

Follow Open Civic Data conventions (used by Open States) rather than inventing
a schema. Core entities:

| Entity | Notes |
|---|---|
| Jurisdiction | `federal`, `state:CO`, `local:...` |
| Body | chamber, committee, subcommittee |
| Session | congress + session for federal |
| Person | legislator; stable external IDs (bioguide, etc.) |
| Membership | person × body × role × term × district × party |
| Bill | identifier, type, title, subjects |
| BillVersion | text as USLM XML + plain text; version type |
| BillAction | normalized event types (see below); date; actor |
| Sponsorship | primary / cosponsor; date |
| Vote | roll call; question; result; totals |
| VotePosition | vote × person × yea/nay/present/absent |
| Event | calendar item: floor, hearing, markup; date; related bills |
| CodeSection | current statute text (redline target); version history |
| Source | URL, `fetched_at`, content hash — on every record |

**Normalized action types:** introduced, referred, hearing, markup, reported,
scheduled, passed_chamber, amended, conference, enrolled, signed, vetoed,
became_law. Adapters map raw actions into these; unknown actions are kept raw
and flagged.

**Rule:** no UI or domain code knows it is federal. Adapters are the only
jurisdiction-specific code.

## 5. Federal adapter — sources

| Need | Source | Notes |
|---|---|---|
| Bills, actions, sponsors, committees, CRS summaries, Record | Congress.gov API v3 | free key via api.data.gov; 5,000 req/hr |
| House roll call votes | Congress.gov API (`house-vote`, beta) | 118th Congress onward |
| Senate roll call votes | senate.gov XML | |
| Bill text | GovInfo (USLM XML) | |
| Current law | US Code XML from Office of the Law Revision Counsel | redline target |
| Members | Congress.gov member endpoint + `unitedstates/congress-legislators` | IDs, districts, social |
| Address → district | Census Geocoder | free |
| Floor schedule (House) | Majority Leader weekly schedule | |
| Committee schedule (House) | docs.house.gov | |
| Senate floor + committee schedules | senate.gov | |
| Committee reports | GovInfo | |
| Cost estimates | CBO | |

## 6. Movement filter

A bill "has movement" when any of these occur: reported out of committee;
scheduled on a floor or committee calendar; roll call vote taken; passed a
chamber; enrolled or signed. Only bills with movement get sections 7.6–7.8.
Everything else gets a tracker page plus the official CRS summary. Expect
hundreds of such bills per year, not thousands.

## 7. Components

### 7.1 Ingest pipeline
Scheduled, incremental, idempotent. Each run records what it fetched and from
where. Coverage checks compare counts against the source (bills per congress,
votes per session, members per chamber).

### 7.2 Your reps
Address → district (Census Geocoder) → current House member and both senators.
Store only the district, not the address, unless the user opts into alerts.

### 7.3 Bill page
Status timeline, sponsors/cosponsors, committee referrals, text versions,
votes with per-member positions, upcoming calendar items, CRS summary. Links
to the official record for every element.

### 7.4 "This week" view
Floor and committee calendars for the coming week, filterable to the user's
reps and followed bills.

### 7.5 Follow and alerts
Follow a bill, a member, or a committee. Email alerts on movement. Push later.

### 7.6 Plain-language layer
- Clause-anchored: each plain-language sentence links to the clause it came
  from. Rendered side by side with the source text.
- Generated by two independent model/prompt configurations; where they
  disagree, the clause is flagged "uncertain."
- Prompts are published in the repo.
- "Report an inaccuracy" on every summary feeds a review queue. No login
  required to report.

### 7.7 Redline engine
- Parse amendatory instructions from USLM bill text ("strike X and insert Y
  in §…", "add at the end…", "redesignate…").
- Apply to the current US Code XML to produce before/after per section.
- Start with strike/insert and add-section. Fall back to showing the raw
  instruction when parsing fails. Track a coverage metric (share of
  instructions rendered) and improve against it.

### 7.8 Why-panel
Attributed sources, labeled: CRS summary, committee report (majority and
minority views), sponsor floor statements from the Record, CBO estimate, and
the strongest opposing statement on record. Never a synthesized "the bill
would…" paragraph without a source label.

## 8. Milestones

| # | Deliverable | Done when |
|---|---|---|
| M1 | Schema + federal adapter: bills, actions, members, votes, text versions, calendars | Nightly ingest runs; coverage checks pass against source counts |
| M2 | Your reps, bill pages, follow/alerts, this-week view | Deployed; a user can find their reps and follow a bill end to end. **Ship here.** |
| M3 | Plain-language layer | Summaries on all movement bills; inaccuracy queue live; prompts published |
| M4 | Redline engine | Coverage metric ≥ 70% of amendatory instructions on movement bills |
| M5 | Why-panel | All movement bills show ≥ 2 attributed sources incl. one opposing |
| Later | State adapter via Plural Open; then section 9 features | |

## 9. Deferred design (keep possible, don't build)

- **Debate:** Pol.is-style statement voting with an opinion-cluster map, not
  comment threads. Surfaces cross-group consensus instead of a "winner."
- **Proposals:** clause-scoped "suggest an edit" with rationale and a
  plain-language impact statement. Versioned; endorsements attach to a version.
- **Delivery ("merge"):** each participant sends a proposal to their own reps.
  A send = shared core (proposal ID, summary) + a personal section in the
  constituent's own words. House delivery via Communicating With Congress API;
  Senate and states via forms/email/mail.
- **Coalition report:** per proposal per district — verified-constituent
  count, districts covered, opinion-cluster spread, growth curve, engagement
  depth, personal-message rate, revision history. Coarse geography with
  minimum counts.
- **Identity tiers:** anonymous reads; verified-human participates;
  verified-constituent sends and counts. Verify only at the send step.
  Document+selfie vendors run roughly $0.30–$1.50 one-time per person
  (Oct 2026); SMS OTP ~$0.06; postcard code ~$0.60–0.90.

## 10. Stack

Elixir + Phoenix LiveView, Ecto + PostgreSQL, Oban for ingest scheduling, Req
for HTTP, Saxy for streaming XML. LiveView fits the product: the bill page,
this-week view, and redline are server-rendered views over a changing dataset,
and alerts/follows map naturally onto PubSub. Detailed conventions are in
`CLAUDE.md`. App name `everyday_citizen`; modules `EverydayCitizen` and `EverydayCitizenWeb`.

## 11. Open questions

- Ops budget and who runs it; governance model for the "contestable" promise.
- Hosting provider (leaning Fly.io; one region near Postgres).
- Whether to open-source from day one (leaning yes; it's part of the
  bias defense).
