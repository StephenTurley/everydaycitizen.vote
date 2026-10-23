# M1: Schema + Federal Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A jurisdiction-agnostic Ecto schema plus a federal adapter that runs nightly, ingests bills, actions, sponsors, text versions, members, committees, roll-call votes and calendars, and passes coverage checks against source counts.

**Architecture:** Domain contexts (`Provenance`, `Legislature`, `Legislation`, `Votes`, `Calendar`) own the tables and know nothing federal. Adapters build plain `TheFloor.Ingest.Records.*` structs (the contract) carrying external IDs and a `SourceRef`; `TheFloor.Ingest.write/2` resolves references and upserts idempotently. Oban workers under `lib/the_floor/adapters/federal/jobs/` do fetch → normalize → `Ingest.write`, nothing else.

**Tech Stack:** Elixir 1.20.4 / OTP 29, Phoenix 1.8, Ecto + PostgreSQL, Oban 2.20, Req 0.5 (+ `Req.Test` stubs), Saxy 1.6, LazyHTML (one HTML source), Credo.

**Spec:** `docs/SPEC.md` (§4 data model, §5 sources, §7.1 ingest, §8 M1). Conventions: `CLAUDE.md`.

## Global Constraints

- Toolchain from `.tool-versions`: `erlang 29.0.6`, `elixir 1.20.4-otp-29`.
- No code outside `lib/the_floor/adapters/federal/` may contain federal concepts (congress, House, Senate, bioguide, LIS, CRS). Enforced by the boundary test in Task 1.
- Every persisted domain row has a non-null `source_id` → `sources(url, fetched_at, content_hash)`. `content_hash` = lowercase hex SHA-256 of the raw response body.
- Normalized action types, exactly: `introduced referred hearing markup reported scheduled passed_chamber amended conference enrolled signed vetoed became_law`. Unmapped actions keep the raw text with `classification = nil` and `unclassified = true`.
- Vote position options, exactly: `yea nay present absent` (raw value kept in `raw_option`).
- Event classifications: `floor hearing markup`; anything else is stored as `other` with the raw type kept.
- Ingest is idempotent: running any job twice on identical source data changes no row counts.
- HTTP only via Req; XML only via Saxy. Tests never touch the network (`Req.Test` plugs, fixtures under `test/support/fixtures/federal/`).
- Congress.gov limit 5,000 req/hr → client-side limiter at one request per 750 ms (4,800/hr).
- Secrets via env vars read in `config/runtime.exs`, documented in `.env.example`. Only new var this milestone: none beyond `CONGRESS_GOV_API_KEY` (already listed).
- Every schema/architecture decision gets an entry appended to `docs/DECISIONS.md`.
- `mix precommit` and `mix credo --strict` pass at the end of every task.

## Review Focus

1. **Congress.gov edits or removes an action after first ingest.** Expect the bill's action list to match the latest fetch, not accumulate duplicates. → Task 4 test `replaces the action set on re-ingest`.
2. **A vote names a member we have no person for** (left mid-term, missing LIS ID). Expect the vote and every other position to save; the orphan position keeps its raw label with `person_id = nil`. → Task 5 test `keeps positions for unknown people`.
3. **Votes not on a bill** (Senate nominations, quorum calls, House journal votes). Expect `bill_id = nil`, no crash. → Tasks 11 and 12 tests `vote without legislation`.
4. **Network failure or 429 mid-run.** Expect the job to retry, the run to be marked `failed`, and the incremental cursor not to advance, so the next run refetches. → Task 6 test `failed run does not advance cursor`.
5. **Bill version whose XML is missing (404) or malformed.** Expect the version row to stay with text fields nil and the job to succeed. → Task 10 tests `missing xml` and `malformed xml`.

---

## File Structure

```
lib/the_floor/
  provenance.ex                     # upsert_source/1, ingest runs, cursors
  provenance/{source,ingest_run}.ex
  legislature.ex                    # queries for jurisdictions/bodies/sessions/people/memberships
  legislature/{jurisdiction,body,legislative_session,person,person_identifier,membership}.ex
  legislation.ex
  legislation/{bill,bill_version,bill_action,sponsorship}.ex
  votes.ex
  votes/{vote,vote_position}.ex
  calendar.ex
  calendar/{event,event_bill}.ex
  ingest.ex                         # write/2 dispatch, Ingest.Run helpers
  ingest/records.ex                 # all Records.* structs (the adapter contract)
  ingest/writer/{legislature,legislation,votes,calendar}.ex
  ingest/coverage.ex                # generic check recording
  ingest/coverage_check.ex          # schema
  ingest/rate_limiter.ex            # named per-host interval limiter
  adapters/federal/
    http.ex                         # Req wrapper → {body, SourceRef}
    congress_gov.ex                 # API client: get/2, paginate/3
    action_classifier.ex
    xml_text.ex                     # Saxy handler: XML → plain text
    normalize/{congress,members,committees,bill,house_vote,senate_vote,committee_meeting,house_floor,senate_floor}.ex
    jobs/{sync_congress,sync_members,sync_bills,sync_bill,sync_bill_text,sync_house_votes,sync_house_vote,sync_senate_votes,sync_senate_vote,sync_committee_meetings,sync_house_floor,sync_senate_floor,coverage}.ex
    coverage.ex                     # federal expected counts
lib/mix/tasks/the_floor.{ingest,coverage}.ex
test/the_floor/...                  # mirrors lib
test/support/fixtures/federal/...   # captured, trimmed real responses
```

Contexts own schemas and read queries; `ingest/writer/*` owns all write paths. Normalizers are pure (`map | xml → [Records.*]`) and are what most adapter tests exercise.

---

### Task 1: Provenance, ingest runs, deps, boundary test

**Files:**
- Modify: `mix.exs` (add `{:oban, "~> 2.20"}`, `{:saxy, "~> 1.6"}`, `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`; change `lazy_html` to all envs), `config/config.exs`, `config/test.exs`, `lib/the_floor/application.ex`
- Create: `priv/repo/migrations/*_add_oban.exs`, `*_create_provenance.exs`, `lib/the_floor/provenance.ex`, `lib/the_floor/provenance/{source,ingest_run}.ex`, `lib/the_floor/ingest/records.ex` (only `SourceRef` for now), `.credo.exs`
- Test: `test/the_floor/provenance_test.exs`, `test/the_floor/boundary_test.exs`

**Interfaces:**
- Produces:
  - `%TheFloor.Ingest.Records.SourceRef{url: String.t(), fetched_at: DateTime.t(), content_hash: String.t()}` and `SourceRef.new(url, body_binary, fetched_at \\ DateTime.utc_now())`
  - `Provenance.upsert_source(%SourceRef{}, run_id :: integer | nil) :: {:ok, %Source{}}` — unique on `(url, content_hash)`; on conflict updates `last_seen_at`.
  - `Provenance.start_run(adapter :: String.t(), job :: String.t()) :: {:ok, %IngestRun{}}`
  - `Provenance.finish_run(run, :succeeded | :failed, stats :: map, error :: String.t() | nil) :: {:ok, %IngestRun{}}`
  - `Provenance.last_succeeded_run(adapter, job) :: %IngestRun{} | nil` (cursor = its `started_at`)

Tables: `sources(id, url, fetched_at, last_seen_at, content_hash, ingest_run_id)`; `ingest_runs(id, adapter, job, status, started_at, finished_at, stats jsonb, error)`. Oban config: `repo: TheFloor.Repo, queues: [ingest: 4, text: 2]`, `testing: :manual` in test.

- [ ] **Step 1: Write failing tests**
  - `upsert_source/2 is idempotent`: same SourceRef twice → one row, `last_seen_at` advanced, `fetched_at` unchanged.
  - `same url, new body creates a new source row`.
  - `SourceRef.new/2 hashes the body`: `SourceRef.new("u", "abc").content_hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"`.
  - `last_succeeded_run/2 ignores failed and running runs`.
  - Boundary test: walks `lib/**/*.ex` excluding `lib/the_floor/adapters/federal/`, asserts no match for `~r/\b(congress|bioguide|senate|house|lis_member|crs)\b/i`. (Phoenix-generated files currently pass; keep the exclusion list to the adapter dir only.)
- [ ] **Step 2: Run** `mix test test/the_floor/provenance_test.exs test/the_floor/boundary_test.exs` → provenance tests FAIL (undefined module); boundary test passes.
- [ ] **Step 3: Implement** deps, migrations, schemas, `Provenance` functions, Oban in supervision tree, `.credo.exs` (`mix credo gen.config`).
- [ ] **Step 4: Run** `mix precommit && mix credo --strict` → all pass.
- [ ] **Step 5: Append to `docs/DECISIONS.md`**: "Provenance as a `sources` table referenced by every row (dedup on url+hash)"; "Oban for ingest"; "CodeSection deferred to M4 (redline), not needed for M1 coverage".
- [ ] **Step 6: Commit** `feat: provenance, ingest runs, Oban, boundary test`

### Task 2: Legislature schema + writer

**Files:**
- Create: migration `*_create_legislature.exs`; `lib/the_floor/legislature.ex`; `lib/the_floor/legislature/*.ex`; `lib/the_floor/ingest.ex`; `lib/the_floor/ingest/writer/legislature.ex`
- Modify: `lib/the_floor/ingest/records.ex`
- Test: `test/the_floor/ingest/writer/legislature_test.exs`, `test/support/data_case.ex` (add `source_ref/0` fixture helper)

**Interfaces:**
- Consumes: `SourceRef`, `Provenance.upsert_source/2`
- Produces records (all have `source: SourceRef`, `jurisdiction: String.t()` unless noted):
  - `Records.Jurisdiction{key, name, classification}` (`"federal" | "state" | "local"`; no `jurisdiction` field)
  - `Records.Body{external_id, name, classification, parent_external_id}` — classification `legislature | chamber | committee | subcommittee`
  - `Records.LegislativeSession{identifier, parent_identifier, name, start_date, end_date}`
  - `Records.Person{identifiers: [{scheme, value}], name, given_name, family_name, image_url}` — no `jurisdiction`
  - `Records.Membership{person: {scheme, value}, body_external_id, role, party, district, start_date, end_date}` — role `member | chair | vice_chair | ranking_member`
- Produces `Ingest.write(record, run_id :: integer | nil) :: {:ok, struct} | {:error, term}` dispatching on struct type.
- Produces queries: `Legislature.get_jurisdiction!(key)`, `Legislature.get_body(jurisdiction_key, external_id)`, `Legislature.get_session(jurisdiction_key, identifier)`, `Legislature.get_person_by_identifier(scheme, value)`, `Legislature.current_memberships(body_id, on :: Date.t())`.

Unique keys: bodies `(jurisdiction_id, external_id)`; sessions `(jurisdiction_id, identifier)`; person_identifiers `(scheme, value)`; memberships `(person_id, body_id, role, start_date)`. A `Person` record matches an existing person if **any** identifier matches; new identifiers are added.

- [ ] **Step 1: Write failing tests**
  - `writes a body tree`: chamber then committee then subcommittee with `parent_external_id`; `Repo.preload(sub, :parent).parent.external_id == committee`.
  - `person matched by any identifier`: write `[{"a","1"}]`, then `[{"a","1"},{"b","9"}]` → one person, two identifiers.
  - `membership upsert is idempotent` and `writing the same records twice leaves counts unchanged`.
  - `membership referencing unknown person returns {:error, {:unknown_person, {"a","x"}}}`.
  - `current_memberships/2 excludes ended memberships and counts a mid-term replacement once`: member A ends 2026-03-01, member B starts 2026-03-05 in same district → on 2026-06-01 only B.
- [ ] **Step 2: Run** `mix test test/the_floor/ingest/writer/legislature_test.exs` → FAIL.
- [ ] **Step 3: Implement** migration, schemas with changesets (`source_id` required), writer using `Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: ...)` inside `Repo.transaction`.
- [ ] **Step 4: Run** test → PASS; `mix precommit`.
- [ ] **Step 5: Commit** `feat: legislature schema and writer`

### Task 3: Rate limiter + federal HTTP + Congress.gov client

**Files:**
- Create: `lib/the_floor/ingest/rate_limiter.ex`, `lib/the_floor/adapters/federal/http.ex`, `lib/the_floor/adapters/federal/congress_gov.ex`
- Modify: `config/runtime.exs`, `config/test.exs`, `lib/the_floor/application.ex`
- Test: `test/the_floor/ingest/rate_limiter_test.exs`, `test/the_floor/adapters/federal/congress_gov_test.exs`

**Interfaces:**
- Produces:
  - `RateLimiter.start_link(name: atom, interval_ms: pos_integer)`; `RateLimiter.acquire(name) :: :ok` blocks until `interval_ms` since the previous grant. Started in the app for `:congress_gov` (750), `:govinfo` (1000), `:house_docs` (1000), `:senate_gov` (2000). Test config sets all to 0.
  - `Federal.HTTP.get(url, opts :: keyword) :: {:ok, %{body: term, raw: binary, source: SourceRef.t()}} | {:error, term}` — opts `:limiter`, `:params`, `:decode` (`:json | :raw`). Uses `Req.new(Application.get_env(:the_floor, :federal_req_options, []))` so tests inject `plug: {Req.Test, TheFloor.Federal}`. Sets `user-agent: "TheFloor/0.1 (+https://thefloor.vote)"`. Retries transient errors and 429 (Req default `retry: :transient`, max 3). `SourceRef.url` excludes the `api_key` param.
  - `CongressGov.get(path :: String.t(), params :: keyword) :: {:ok, map, SourceRef.t()} | {:error, term}` — base `https://api.congress.gov/v3`, adds `api_key` from `Application.fetch_env!(:the_floor, :congress_gov_api_key)` and `format=json`.
  - `CongressGov.paginate(path, list_key :: String.t(), params) :: Enumerable.t({map, SourceRef.t()})` — `limit=250`, follows `pagination.next` until nil.
  - `CongressGov.count(path, params) :: {:ok, non_neg_integer}` — `limit=1`, returns `pagination.count`.
- Config: `runtime.exs` reads `CONGRESS_GOV_API_KEY` (raise in `:prod` if missing; `nil` allowed in dev/test).

- [ ] **Step 1: Write failing tests**
  - `acquire/1 spaces grants`: interval 50 → three acquires take ≥ 100 ms.
  - `get/2 strips api_key from source url and hashes the raw body`.
  - `paginate/3 follows next links`: stub two pages (2 + 1 items) → 3 items.
  - `get/2 returns {:error, _} after retries on 503` (set `retry_delay: 0` via req options in test).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `mix precommit`.
- [ ] **Step 5: Commit** `feat: rate limiter and Congress.gov client`

### Task 4: Legislation schema + writer

**Files:**
- Create: migration `*_create_legislation.exs`; `lib/the_floor/legislation.ex`; `lib/the_floor/legislation/*.ex`; `lib/the_floor/ingest/writer/legislation.ex`
- Modify: `lib/the_floor/ingest/records.ex`, `lib/the_floor/ingest.ex`
- Test: `test/the_floor/ingest/writer/legislation_test.exs`

**Interfaces:**
- Consumes: Task 2 records/queries.
- Produces records:
  - `Records.Bill{session_identifier, external_id, identifier, classification, title, subjects: [String.t()], from_body_external_id, introduced_on, updated_at_source}` — classification `bill | resolution | joint_resolution | concurrent_resolution`
  - `Records.BillActions{bill_external_id, actions: [%Records.BillAction{position, date, description, raw_type, raw_code, classification, actor_body_external_id}]}` — **replaces** the bill's full action set.
  - `Records.Sponsorships{bill_external_id, sponsorships: [%{person: {scheme, value}, classification: "primary" | "cosponsor", date, withdrawn_on}]}` — replaces the set; unknown people skipped and counted in the return value `{:ok, %{written: n, skipped_people: [ref]}}`.
  - `Records.BillVersion{bill_external_id, code, classification, date, xml_url, text_url}`
  - `Records.BillVersionText{bill_external_id, code, xml, xml_schema, plain_text}` — updates only those columns.
- Produces queries: `Legislation.get_bill(jurisdiction_key, external_id)`, `Legislation.count_bills(session_id)`, `Legislation.list_unclassified_actions(limit)`, `Legislation.versions_missing_text(limit)`.

Columns of note: `bill_actions.unclassified :: boolean` (= `classification is nil`), `bill_versions.xml :: text`, `plain_text :: text`, `xml_schema :: string` (`"uslm" | "other"`).

- [ ] **Step 1: Write failing tests**
  - `replaces the action set on re-ingest`: write 3 actions, then 2 (one edited) → exactly those 2 rows.
  - `action with nil classification is flagged unclassified`.
  - `sponsorships skip unknown people and report them`.
  - `BillVersionText updates text without touching date/urls`.
  - `bill referencing unknown session returns {:error, {:unknown_session, "x"}}`.
  - idempotency: writing the same Bill, BillActions, Sponsorships twice leaves counts unchanged.
- [ ] **Step 2–4:** run → FAIL, implement (set replacement = delete-not-in + upsert inside one transaction), run → PASS, `mix precommit`.
- [ ] **Step 5: Commit** `feat: legislation schema and writer`

### Task 5: Votes + Calendar schema + writer

**Files:**
- Create: migration `*_create_votes_and_calendar.exs`; `lib/the_floor/votes.ex`, `lib/the_floor/votes/*.ex`, `lib/the_floor/calendar.ex`, `lib/the_floor/calendar/*.ex`, `lib/the_floor/ingest/writer/{votes,calendar}.ex`
- Modify: `lib/the_floor/ingest/records.ex`, `lib/the_floor/ingest.ex`
- Test: `test/the_floor/ingest/writer/votes_test.exs`, `test/the_floor/ingest/writer/calendar_test.exs`

**Interfaces:**
- Produces records:
  - `Records.Vote{body_external_id, session_identifier, external_id, identifier, question, result, passed :: boolean | nil, voted_at :: DateTime.t() (UTC), bill_external_id | nil, counts: %{yea, nay, present, absent}, positions: [%{person: {scheme, value} | nil, raw_label, option, raw_option}]}` — positions replace the set.
  - `Records.Event{body_external_id | nil, external_id, classification, raw_classification, title, start_at :: DateTime.t(), all_day :: boolean, location, bill_external_ids: [String.t()], raw_bill_labels: [String.t()]}` — `event_bills` rows link resolved bills; unresolved labels stored on the event (`unresolved_bill_labels :: {:array, :string}`).
- Produces queries: `Votes.count_votes(body_id, session_id)`, `Calendar.list_events(from :: DateTime.t(), to :: DateTime.t())`.

- [ ] **Step 1: Write failing tests**
  - `keeps positions for unknown people`: one position references `{"x","nope"}` → saved with `person_id: nil`, `raw_label` kept, other positions linked.
  - `vote without legislation` → `bill_id: nil`.
  - `re-ingesting a vote replaces positions` and idempotent counts.
  - `event links known bills and keeps unknown labels`.
  - `option outside yea/nay/present/absent is rejected by changeset`.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat: votes and calendar schema and writer`

### Task 6: Federal bootstrap (jurisdiction, chambers, sessions) + run wrapper

**Files:**
- Create: `lib/the_floor/adapters/federal/normalize/congress.ex`, `lib/the_floor/adapters/federal/jobs/sync_congress.ex`, `lib/the_floor/adapters/federal/job.ex`
- Test: `test/the_floor/adapters/federal/normalize/congress_test.exs`, `test/the_floor/adapters/federal/job_test.exs`, fixture `test/support/fixtures/federal/congress_gov/congress_119.json`

**Interfaces:**
- Produces:
  - `Federal.Job.run(job_name :: String.t(), (run_id, cursor :: DateTime.t() | nil -> {:ok, stats} | {:error, term})) :: :ok | {:error, term}` — wraps `Provenance.start_run/finish_run`, adapter `"federal"`. Used by every list-level job.
  - `Normalize.Congress.records(json, SourceRef) :: [record]` — `Jurisdiction{key: "federal", name: "United States Congress", classification: "federal"}`; bodies `"congress"` (legislature), `"house"`, `"senate"` (chamber, parent `"congress"`); sessions `"119"` and `"119-1"`, `"119-2"` (parent `"119"`) with dates from the `sessions` array (earliest start / latest end across chambers).
  - Worker `Jobs.SyncCongress` (args `%{"congress" => 119}`), queue `ingest`. Configured current congress: `config :the_floor, :federal, congress: 119`.
- Fixture: `curl "https://api.congress.gov/v3/congress/119?format=json&api_key=$CONGRESS_GOV_API_KEY"`.

- [ ] **Step 1: Write failing tests**
  - Normalizer produces the three bodies and three sessions with fixture dates.
  - `failed run does not advance cursor`: `Job.run` with a fun returning `{:error, :boom}` → run status `failed`; `Provenance.last_succeeded_run` still returns the earlier succeeded run.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Decision log:** "Federal session = congress; sub-sessions `119-1`/`119-2` for vote numbering."
- [ ] **Step 6: Commit** `feat(federal): bootstrap jurisdiction, chambers, sessions`

### Task 7: Members and committees

**Files:**
- Create: `lib/the_floor/adapters/federal/normalize/{members,committees}.ex`, `jobs/sync_members.ex`
- Test: `test/the_floor/adapters/federal/normalize/{members,committees}_test.exs`; fixtures (trimmed to ~3 entries each) under `test/support/fixtures/federal/legislators/`: `legislators-current.json`, `legislators-historical.json`, `committees-current.json`, `committee-membership-current.json`

Source: `https://unitedstates.github.io/congress-legislators/<file>.json` (Congress.gov member endpoint is used for coverage in Task 15). Historical file is filtered to people with a term ending on/after the session start (needed for votes cast by members who left).

**Interfaces:**
- Produces:
  - `Normalize.Members.records(legislators :: [map], session_start :: Date.t(), SourceRef) :: [Person | Membership]` — identifiers schemes `"bioguide"`, `"lis"`, `"govtrack"`, `"thomas"` (only those present). One chamber `Membership` per term overlapping the session. District: House `"#{state}-#{district}"`, district `0` → `"#{state}-AL"`; Senate `state`. Party from term.
  - `Normalize.Committees.records(committees, memberships, SourceRef) :: [Body | Membership]` — external IDs: committee `String.downcase(thomas_id) <> "00"`, subcommittee `String.downcase(parent_thomas_id <> sub_thomas_id)` (matches Congress.gov `systemCode`); joint committees parent `"congress"`. Roles from `title`: `"Chairman"/"Chair"` → chair, `"Ranking Member"` → ranking_member, `"Vice Chair..."` → vice_chair, else member.
  - Worker `Jobs.SyncMembers`: fetch 4 files, write people, then chamber memberships, then committee bodies, then committee memberships.

- [ ] **Step 1: Write failing tests**: at-large district `"AK-AL"`; senator district `"CO"`; member with two terms in range → two memberships; historical member whose last term ended before session start excluded; committee `HSAG` → `"hsag00"`, subcommittee `"hsag03"` with parent `"hsag00"`; `"Ranking Member"` role mapping.
- [ ] **Step 2–4:** FAIL → implement → PASS (also a worker test with `Req.Test` stubs asserting counts after `perform_job/2` twice are equal) → `mix precommit`.
- [ ] **Step 5: Decision log:** "Members/committees from unitedstates/congress-legislators (only source with LIS IDs needed for Senate votes)."
- [ ] **Step 6: Commit** `feat(federal): members and committees`

### Task 8: Action classifier

**Files:**
- Create: `lib/the_floor/adapters/federal/action_classifier.ex`
- Test: `test/the_floor/adapters/federal/action_classifier_test.exs`

**Interfaces:**
- Produces `ActionClassifier.classify(%{"text" => String.t(), "type" => String.t() | nil}) :: String.t() | nil`.

Rules evaluated in this order, first match wins (case-insensitive regex on `text`):

| Pattern | Type |
|---|---|
| `became public law\|became private law` | became_law |
| `vetoed by president\|pocket veto` | vetoed |
| `signed by president` | signed |
| `presented to president\|enrolled bill signed\|enrolled measure` | enrolled |
| `conference report\|conferees` | conference |
| `^introduced in` | introduced |
| `passed\|agreed to in (house\|senate)` and not `amendment` | passed_chamber |
| `amendment .* agreed to\|amendment \(.+\) agreed` | amended |
| `^reported\|reported by\|reported \(amended\)` | reported |
| `mark-?up\|ordered to be reported` | markup |
| `hearings? held` | hearing |
| `referred to\|read twice and referred` | referred |
| `placed on .* calendar` | scheduled |

- [ ] **Step 1: Write failing table test** with these exact inputs → outputs:
  `"Introduced in House"`→introduced; `"Read twice and referred to the Committee on Finance."`→referred; `"Referred to the House Committee on Ways and Means."`→referred; `"Subcommittee Hearings Held"`→hearing; `"Committee Consideration and Mark-up Session Held"`→markup; `"Ordered to be Reported (Amended) by Voice Vote."`→markup; `"Reported (Amended) by the Committee on Energy and Commerce. H. Rept. 119-12."`→reported; `"Placed on the Union Calendar, Calendar No. 12."`→scheduled; `"Passed/agreed to in House: On passage Passed by recorded vote: 220 - 207 (Roll no. 45)."`→passed_chamber; `"Passed Senate without amendment by Unanimous Consent."`→passed_chamber; `"Amendment SA 12 agreed to in Senate by Voice Vote."`→amended; `"Conference report H. Rept. 119-50 filed."`→conference; `"Presented to President."`→enrolled; `"Signed by President."`→signed; `"Vetoed by President."`→vetoed; `"Became Public Law No: 119-4."`→became_law; `"Motion to reconsider laid on the table Agreed to without objection."`→nil.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat(federal): action classifier`

### Task 9: Bills (detail, actions, sponsors, subjects, version metadata)

**Files:**
- Create: `lib/the_floor/adapters/federal/normalize/bill.ex`, `jobs/sync_bills.ex`, `jobs/sync_bill.ex`
- Test: `test/the_floor/adapters/federal/normalize/bill_test.exs`, `test/the_floor/adapters/federal/jobs/sync_bill_test.exs`; fixtures `congress_gov/bill_119_hr_1/{bill,actions,cosponsors,subjects,text}.json`, `bill_list_page.json` (pick a bill that has ≥ 2 text versions and ≥ 1 withdrawn cosponsor)

**Interfaces:**
- Consumes: `CongressGov`, `ActionClassifier.classify/1`, `Federal.Job.run/2`, Task 4 records.
- Produces:
  - Bill external_id `"#{congress}-#{lowercase type}-#{number}"` (e.g. `"119-hr-1"`); identifier display form from type map `HR→"H.R."`, `S→"S."`, `HRES→"H.Res."`, `SRES→"S.Res."`, `HJRES→"H.J.Res."`, `SJRES→"S.J.Res."`, `HCONRES→"H.Con.Res."`, `SCONRES→"S.Con.Res."` + `" #{number}"`. Classification from the same type map.
  - `Normalize.Bill.bill(json, SourceRef)`, `.actions(json, bill_external_id, SourceRef)` (positions in chronological order, oldest = 0), `.sponsorships(bill_json, cosponsors_json, ...)`, `.versions(text_json, ...)` — version `code` from the GovInfo package suffix (`ih`, `rh`, `eh`, `enr` …), `xml_url` = the `"Formatted XML"` format URL, `text_url` = `"Formatted Text"` URL.
  - `Jobs.SyncBills` (args `%{"congress" => 119}`): `Job.run("sync_bills", …)` paging `/bill/119?sort=updateDate+asc&fromDateTime=<cursor ISO8601Z>` (no cursor → full backfill), enqueuing `Jobs.SyncBill` per bill with `unique: [period: 3600, keys: [:congress, :type, :number]]`.
  - `Jobs.SyncBill` (args `congress, type, number, run_id`): 5 requests (detail, `/actions`, `/cosponsors`, `/subjects`, `/text`), writes Bill → BillActions → Sponsorships → each BillVersion, then enqueues `Jobs.SyncBillText` for versions whose text is nil.

- [ ] **Step 1: Write failing tests**: external_id/identifier for `HJRES 5` → `"119-hjres-5"`/`"H.J.Res. 5"`; actions chronological with classifications; withdrawn cosponsor has `withdrawn_on`; sponsor is `"primary"`; version codes from fixture; `SyncBill` run twice → identical counts; `SyncBills` with a stubbed 2-item list enqueues 2 jobs (`assert_enqueued`).
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat(federal): bill ingest`

### Task 10: Bill text (XML + plain text)

**Files:**
- Create: `lib/the_floor/adapters/federal/xml_text.ex`, `jobs/sync_bill_text.ex`
- Test: `test/the_floor/adapters/federal/xml_text_test.exs`, `test/the_floor/adapters/federal/jobs/sync_bill_text_test.exs`; fixtures `govinfo/BILLS-119hr1ih.uslm.xml` (trimmed), `govinfo/malformed.xml`

**Interfaces:**
- Produces:
  - `XmlText.plain_text(xml :: binary) :: {:ok, String.t()} | {:error, term}` — Saxy handler concatenating character data; block-level elements (`section`, `paragraph`, `subsection`, `p`, `heading`, `num`… treat any element end as a separator) join with `"\n"`; collapse runs of whitespace within lines.
  - `Jobs.SyncBillText` (queue `text`, args `bill_external_id, code`): try USLM at `https://www.govinfo.gov/content/pkg/BILLS-#{congress}#{type}#{number}#{code}/uslm/BILLS-#{…}.xml` (limiter `:govinfo`); on 404 fall back to the version's `xml_url` with `xml_schema: "other"`; on 404 for both or parse error, return `:ok` leaving text nil and log at `:warning`.
- First step of implementation: fetch one real USLM URL for a 119th bill and confirm the path; if GovInfo's layout differs, update the URL builder and note it in DECISIONS.

- [ ] **Step 1: Write failing tests**: `plain_text` of fixture contains the section heading and its body text on separate lines; `missing xml` (both 404) → job `:ok`, text nil; `malformed xml` → job `:ok`, text nil; USLM success → `xml_schema == "uslm"`; fallback → `"other"`.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat(federal): bill text ingest`

### Task 11: House roll-call votes

**Files:**
- Create: `normalize/house_vote.ex`, `jobs/sync_house_votes.ex`, `jobs/sync_house_vote.ex`
- Test: `test/the_floor/adapters/federal/normalize/house_vote_test.exs`; fixtures `congress_gov/house_vote_list.json`, `house_vote_119_1_17.json`, `house_vote_119_1_17_members.json`, plus one vote with no legislation

Source: `/house-vote/{congress}/{session}` list, `/house-vote/{c}/{s}/{roll}` detail, `/house-vote/{c}/{s}/{roll}/members`. The endpoint is beta: capture fixtures first and take field names from them.

**Interfaces:**
- Produces `Normalize.HouseVote.vote(detail_json, members_json, SourceRef) :: Records.Vote` — external_id `"house-#{congress}-#{session}-#{roll}"`, session_identifier `"#{congress}-#{session}"`, body `"house"`, `voted_at` converted from the source's Eastern-time timestamp to UTC (add `{:tz, "~> 0.28"}`, set `config :elixir, :time_zone_database, Tz.TimeZoneDatabase`); options `Yea|Aye → yea`, `Nay|No → nay`, `Present → present`, `Not Voting → absent`; person `{"bioguide", id}`; bill from legislation type/number via Task 9's external_id rule, nil when absent. `passed` true when result matches `~r/passed|agreed/i`, false when `~r/failed|rejected/i`, else nil.
- `Jobs.SyncHouseVotes` (args `congress`, `session`): enqueue one `SyncHouseVote` per roll not already stored (or updated since cursor).

- [ ] **Step 1: Write failing tests**: option mapping incl. `"Aye"`; a July timestamp `2025-07-02T14:31:00-04:00` → `~U[2025-07-02 18:31:00Z]` and a January one with `-05:00`; `vote without legislation` → `bill_external_id: nil`; counts match the fixture totals.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat(federal): House votes`

### Task 12: Senate roll-call votes

**Files:**
- Create: `normalize/senate_vote.ex`, `jobs/sync_senate_votes.ex`, `jobs/sync_senate_vote.ex`
- Test: `test/the_floor/adapters/federal/normalize/senate_vote_test.exs`; fixtures `senate/vote_menu_119_1.xml`, `senate/vote_119_1_00001.xml` (on a bill), `senate/vote_119_1_nomination.xml`

Source: menu `https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_#{c}_#{s}.xml`; detail `https://www.senate.gov/legislative/LIS/roll_call_votes/vote#{c}#{s}/vote_#{c}_#{s}_#{zero-pad 5}.xml`. Limiter `:senate_gov`. Parse with `Saxy.SimpleForm`.

**Interfaces:**
- Produces `Normalize.SenateVote.menu(xml) :: [roll :: pos_integer]` and `.vote(xml, SourceRef) :: Records.Vote` — external_id `"senate-#{c}-#{s}-#{roll}"`; `vote_date` like `"January 9, 2025, 12:04 PM"` parsed as America/New_York → UTC (Tz from Task 11); `Yea|Guilty → yea`, `Nay|Not Guilty → nay`, `Present → present`, `Not Voting → absent`; person `{"lis", lis_member_id}`; bill from `document_type`/`document_number` only when type is a bill type (`S.`, `H.R.`, `S.J.Res.` …), nil for `PN` nominations.

- [ ] **Step 1: Write failing tests**: menu returns roll numbers; nomination vote → `bill_external_id: nil`; date parse → UTC; positions keyed by LIS IDs; count totals.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Commit** `feat(federal): Senate votes`

### Task 13: Committee meetings (both chambers)

**Files:**
- Create: `normalize/committee_meeting.ex`, `jobs/sync_committee_meetings.ex`
- Test: `normalize/committee_meeting_test.exs`; fixtures `congress_gov/committee_meeting_list.json`, `committee_meeting_house_<id>.json`, `committee_meeting_senate_<id>.json`

Source: Congress.gov `/committee-meeting/{congress}/{chamber}` list + detail (one primary source covers House and Senate committee schedules; replaces docs.house.gov for committees).

**Interfaces:**
- Produces `Normalize.CommitteeMeeting.event(detail_json, SourceRef) :: Records.Event` — external_id `"meeting-#{eventId}"`; body from committee `systemCode`; `type` `Hearing → hearing`, `Markup → markup`, `Meeting` and others → `other` (raw kept); bills from `relatedItems.bills` via Task 9 external_id rule; `start_at` UTC.
- `Jobs.SyncCommitteeMeetings`: list with `fromDateTime=cursor`, fetch details, write. Re-fetch meetings dated in the next 14 days on every run (they get rescheduled/cancelled; cancelled → keep row, title prefixed by source status field into `raw_classification`).

- [ ] **Step 1: Write failing tests**: hearing and markup mapping; `"Meeting"` → `other`; related bills resolved to external_ids; unknown committee code → event with `body_external_id` nil, not an error.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Decision log:** "Committee calendars from Congress.gov committee-meeting (both chambers, typed) instead of docs.house.gov + senate.gov."
- [ ] **Step 6: Commit** `feat(federal): committee meetings`

### Task 14: Floor schedules (House + Senate)

**Files:**
- Create: `normalize/{house_floor,senate_floor}.ex`, `jobs/{sync_house_floor,sync_senate_floor}.ex`
- Test: `normalize/house_floor_test.exs`, `normalize/senate_floor_test.exs`; fixtures `house_docs/floor_week.xml`, `senate/floor_schedule.htm`

Sources:
- House: `https://docs.house.gov/floor/Download.aspx?file=/billsthisweek/#{yyyymmdd}/#{yyyymmdd}.xml` for the Monday of the current and next week (official Clerk/Majority feed; same content as the Majority Leader schedule, machine-readable). Limiter `:house_docs`. Missing week (404) → no events, `:ok`.
- Senate: `https://www.senate.gov/legislative/schedule/floor_schedule.htm`, parsed with LazyHTML. Most fragile source in M1.

**Interfaces:**
- Produces `Normalize.HouseFloor.events(xml, SourceRef) :: [Records.Event]` — one event per floor item: classification `floor`, body `"house"`, `all_day: true`, `start_at` = week date 00:00 America/New_York → UTC, title = item text, external_id `"house-floor-#{week}-#{legis-num normalized}"`, bill from `legis-num`.
- Produces `Normalize.SenateFloor.events(html, SourceRef) :: [Records.Event]` — one event per scheduled day; bills by regex `~r/\b(S|H\.R|S\.J\.Res|H\.J\.Res|S\.Res|H\.Res)\.?\s?(\d+)/` within that day's text; external_id `"senate-floor-#{date}"`.
- Both jobs log `:warning` and record `stats.items = 0` when the source parses to zero events on a weekday when the chamber is in session (coverage surfaces it).

- [ ] **Step 1: Write failing tests**: House fixture item count and bill resolution (`"H.R. 1234"` → `"119-hr-1234"`); Senate fixture yields expected dates and bills; empty/404 House week → `[]`.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit`.
- [ ] **Step 5: Decision log:** "House floor from docs.house.gov weekly XML instead of the Majority Leader HTML page."
- [ ] **Step 6: Commit** `feat(federal): floor schedules`

### Task 15: Coverage checks, nightly schedule, mix tasks, docs

**Files:**
- Create: migration `*_create_coverage_checks.exs`; `lib/the_floor/ingest/{coverage,coverage_check}.ex`; `lib/the_floor/adapters/federal/coverage.ex`; `jobs/coverage.ex`; `lib/mix/tasks/the_floor.ingest.ex`, `lib/mix/tasks/the_floor.coverage.ex`
- Modify: `config/config.exs` (Oban Cron), `README.md`, `.env.example` (comment for the key), `CLAUDE.md` (Build and test: new mix tasks)
- Test: `test/the_floor/ingest/coverage_test.exs`, `test/the_floor/adapters/federal/coverage_test.exs`

**Interfaces:**
- Produces:
  - `Ingest.Coverage.record(run_id, name :: String.t(), expected :: integer, actual :: integer, tolerance :: float) :: {:ok, %CoverageCheck{passed: boolean}}` — passes iff `actual <= expected and actual >= floor(expected * (1 - tolerance))`.
  - `Ingest.Coverage.latest() :: [%CoverageCheck{}]` (latest row per name).
  - `Federal.Coverage.checks(congress) :: [{name, expected_fun, actual_fun, tolerance}]`:
    - `bills:119` — `CongressGov.count("/bill/119")` vs `Legislation.count_bills`, tolerance `0.005` (bills introduced during the run).
    - `votes:house:119-N` — `CongressGov.count("/house-vote/119/N")` vs `Votes.count_votes`, tolerance `0`.
    - `votes:senate:119-N` — length of the Senate vote menu vs `Votes.count_votes`, tolerance `0`.
    - `members:house`, `members:senate` — current members per chamber from Congress.gov `/member/congress/119?currentMember=true` (paginate, group by latest term chamber) vs `Legislature.current_memberships(body_id, Date.utc_today())`, tolerance `0`.
  - `Jobs.Coverage` writes all checks inside `Job.run("coverage", …)`.
  - Oban Cron (America/New_York, `Oban.Plugins.Cron`): `02:00 SyncCongress`, `02:10 SyncMembers`, `02:30 SyncBills`, `02:40 SyncHouseVotes` and `SyncSenateVotes` (current session), `02:50 SyncCommitteeMeetings`, `03:00 SyncHouseFloor`, `SyncSenateFloor`, `06:00 Coverage`.
  - `mix the_floor.ingest [job]` enqueues one or all jobs now; `mix the_floor.coverage` prints `name expected actual PASS/FAIL` from `Coverage.latest/0` and exits non-zero if any fail.
- [ ] **Step 1: Write failing tests**: tolerance boundaries (`expected 1000, actual 995, 0.005` → pass; `994` → fail; `actual > expected` → fail); federal checks with stubbed counts record one row per check; current-membership count excludes a member who left.
- [ ] **Step 2–4:** FAIL → implement → PASS → `mix precommit && mix credo --strict`.
- [ ] **Step 5: Live verification (M1 done-when):** with a real `CONGRESS_GOV_API_KEY`, `mix the_floor.ingest` on a dev DB, let the backfill finish (≈ 15k bills × 5 calls at 4,800/hr ≈ 16 h on first run), then `mix the_floor.ingest coverage && mix the_floor.coverage` → all PASS. Record the result and any failures in `docs/DECISIONS.md`.
- [ ] **Step 6: Commit** `feat: coverage checks and nightly ingest schedule`
