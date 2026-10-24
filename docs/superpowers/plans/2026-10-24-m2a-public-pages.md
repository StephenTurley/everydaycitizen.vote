# M2a Public Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone can enter an address, see their reps, open a rep's activity feed, open a bill page, and see what is scheduled this week, with no account.

**Architecture:** First fill the data the pages need (correct action types, CRS summaries, vote types, bill sections), each written by the federal adapter and read through jurisdiction-agnostic domain functions. Then add read models (`TheFloor.Reps`, `TheFloor.Activity`, bill-page and calendar queries) and LiveViews that render the approved mockups. Accounts, following and email are plan M2b.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto/PostgreSQL, Oban, Req, Saxy, LazyHTML (already deps).

**Spec:** `docs/superpowers/specs/2026-10-23-m2-frontend-design.md` (approved 2026-10-24) and `docs/SPEC.md`. Mockups: https://claude.ai/artifact/CFipwnFH7uqiZmUMf1w23J, boards "A · One rep at a time" and "Bill page (M2)".

## Global Constraints

- No UI or domain code may know it is federal; `test/the_floor/boundary_test.exs` must keep passing (no "congress", "bioguide", "senate", "house", "lis_member", "crs" under `lib/` outside `lib/the_floor/adapters/federal/`, comments included). Federal wording on pages comes from stored names (body names, identifiers).
- The pages' jurisdiction comes from `config :the_floor, :default_jurisdiction, "federal"`, never a literal in UI or domain code.
- Every record carries provenance; every page item links to its official record.
- The product never characterizes motives; summaries are always labeled with their author ("Congressional Research Service" comes from the stored summary's source label, not code).
- No street address is stored or logged: add `"address"` to `config :phoenix, :filter_parameters`; it never appears in a URL; Sentry already drops query strings.
- Phone first (390 px), works on desktop. Accessibility: real links/buttons/labels, 44 px targets, contrast ≥ 4.5:1, vote positions differ by fill and label, never color alone.
- Look (from the mockups): Public Sans, ground #F4F5F6, cards #FFFFFF with 1px #DADDE1 border and 12px radius, ink #15171A, secondary text #4A5058, accent #0B5563. "Yea" solid #15171A chip, "Nay" outlined chip, "Not voting"/"No vote yet" #E6E8EB chip. No party colors.
- Client JS: LiveView hooks only. `mix precommit` and `mix credo --strict` clean before every commit; DECISIONS.md entry for each schema change.

## Review Focus

1. An address the geocoder cannot match, or a geocoder outage: the person sees "We couldn't find that address" (or "Address lookup is unavailable, try again") and the form keeps what they typed; nothing crashes. Pinned in Task 6.
2. A district with no senators or a non-voting delegate (DC, territories): the reps row shows only the members that exist, labeled as stored. Pinned in Task 6.
3. A simple resolution (one chamber, never becomes law): the status line ends at "Agreed to", not an empty "Law" step. Pinned in Task 9.
4. A bill with no text versions yet, no summary, or no votes: those sections say so in one line rather than rendering empty boxes. Pinned in Task 9.
5. A rep with no activity in the selected filter, or a vacant seat: the feed says "Nothing yet" and the rep row still renders. Pinned in Task 8.

---

### Task 1: Procedural floor motions are not passage

**Files:** Modify `lib/the_floor/adapters/federal/action_classifier.ex`; Test `test/the_floor/adapters/federal/action_classifier_test.exs`

- [ ] Test `motions and cloture are not passage`:
  - `classify(%{"text" => "Motion to proceed to consideration of measure agreed to in Senate by Yea-Nay Vote. 77 - 22. Record Vote Number: 233."})` → `nil`
  - `"Cloture on the motion to proceed to the measure invoked in Senate by Yea-Nay Vote. 74 - 24."` → `nil`
  - `"Passed Senate with an amendment by Yea-Nay Vote. 77 - 22. Record Vote Number: 250."` → `"passed_chamber"`
  - All existing classifier cases still pass.
- [ ] Run; expect the first two to FAIL (`"passed_chamber"`).
- [ ] Add a first rule matching `~r/^(motion|cloture)\b/i` that makes `classify/1` return `nil` (a skip marker in the rule list, not a new action type).
- [ ] Add a release task `TheFloor.Release.reclassify_actions/0` that re-runs the configured adapters' classification over stored actions. It goes through a new adapter callback `reclassify_actions/0` in `TheFloor.Adapters.Federal.Jobs` (registry module), which uses a domain function `Legislation.update_action_classifications([{action_id, classification}])` (one `UPDATE … FROM (VALUES …)` per 1,000). Test: stored action with the motion text, classification `passed_chamber`, becomes `nil` and `unclassified: true`.
- [ ] Commit `fix(federal): motions and cloture are not chamber passage`.

### Task 2: Bulk parser keeps repeated elements

**Files:** Modify `lib/the_floor/adapters/federal/normalize/bill_status.ex`; Test `test/the_floor/adapters/federal/normalize/bill_status_test.exs`

- [ ] Test `repeated non-item children become a list`: `<bill><summaries><summary><versionCode>00</versionCode></summary><summary><versionCode>36</versionCode></summary></summaries>…` → `parts.detail["bill"]["summaries"]["summary"] == [%{"versionCode" => "00"}, %{"versionCode" => "36"}]`; a single `<summary>` stays a map. Also the hr22 fixture now yields a `"summaries"` value with every summary in the file.
- [ ] Run; FAIL (last one wins).
- [ ] In `container/1`, group children by name: a name seen once maps to its value, a name repeated maps to the list of values. Expose `parts.summaries :: [map()]` (API shape: each `%{"versionCode", "actionDate", "actionDesc", "updateDate", "text"}`; `[]` when none).
- [ ] Parity tests still pass. Commit `fix(federal): BILLSTATUS repeated elements kept as lists`.

### Task 3: CRS summaries stored

**Files:** Migration `priv/repo/migrations/20261024100000_create_bill_summaries.exs`; Create `lib/the_floor/legislation/bill_summary.ex`, `lib/the_floor/ingest/safe_html.ex`; Modify `lib/the_floor/ingest/records.ex` (add `Records.BillSummaries`), `lib/the_floor/ingest.ex`, `lib/the_floor/ingest/writer/legislation.ex`, `lib/the_floor/legislation.ex`, `lib/the_floor/adapters/federal/normalize/bill.ex`, `lib/the_floor/adapters/federal/bill_writer.ex`, `lib/the_floor/adapters/federal/jobs/sync_bill.ex`, `lib/the_floor/adapters/federal/jobs/bulk_bills_chunk.ex`; Create `lib/the_floor/adapters/federal/jobs/backfill_bill_summaries.ex`; Tests beside each.

**Interfaces:**
- Produces: table `bill_summaries` (`bill_id` FK cascade, `version_code` string null, `action_date` date, `action_description` string, `author` string not null, `html` text not null, `updated_at_source` utc_datetime_usec, `source_id` FK, timestamps; unique `[bill_id, version_code, action_date]`).
- `Records.BillSummaries{jurisdiction, bill_external_id, author, summaries: [%{version_code, action_date, action_description, html, updated_at_source}], source}`. The set replaces the stored set for the bill, like `BillActions`.
- `TheFloor.Ingest.SafeHtml.sanitize(html :: String.t()) :: String.t()`, which keeps only `p ul ol li strong em b i br` (attributes dropped) via LazyHTML; text is escaped.
- `Legislation.latest_summary(bill :: Bill.t()) :: BillSummary.t() | nil`: latest `action_date`.
- `Normalize.Bill.summaries(summaries :: [map()], bill_external_id, source) :: Records.BillSummaries.t()` with `author: "Congressional Research Service"`.

Steps:
- [ ] Tests:
  - `SafeHtml` strips `<script>`, `onclick` and `<a href>` but keeps `<p><strong>`.
  - The writer replaces the summary set.
  - `latest_summary/1`.
  - Normalizer on the hr22 BILLSTATUS fixture: count equals the file's `<summary>` count, author set.
  - `SyncBill` fetches `/bill/{c}/{t}/{n}/summaries` (add a captured fixture `congress_gov/bill_119_hr_22/summaries.json` from the live API) and stores them.
  - A bulk chunk stores them.
  - `BackfillBillSummaries` (a `BulkBatch` coordinator reusing `SyncBills`' fan-out, with chunk args `"only" => "summaries"`, which make `BulkBillsChunk` write only the summary set) fills summaries for bills stored without any.
- [ ] Run; FAIL. Implement. Also extract `SyncBills`' fan-out into `BulkBillsChunk.chunks(congress) :: {:ok, [map()]} | {:error, term()}` so both coordinators share it.
- [ ] Register `{"bill_summaries", BackfillBillSummaries, %{}}` as a by-name job that `all` excludes: add an `on_demand/0` list to the registry and make `TheFloor.Ingest.Jobs.select/1` look in both. Test `mix the_floor.ingest` (all) does not enqueue it.
- [ ] DECISIONS entry. Commit `feat: CRS summaries stored per bill`.

### Task 4: Votes have a type

**Files:** Migration `…_add_vote_classification.exs`; Create `lib/the_floor/adapters/federal/vote_classifier.ex`; Modify `lib/the_floor/votes/vote.ex`, `lib/the_floor/ingest/records.ex` (`Vote.classification`), `lib/the_floor/ingest/writer/votes.ex`, `lib/the_floor/adapters/federal/normalize/house_vote.ex`, `lib/the_floor/adapters/federal/normalize/senate_voteview.ex`, `lib/the_floor/votes.ex`, registry (`reclassify_votes` on demand).

**Interfaces:**
- `votes.classification` string, values `passage cloture amendment nomination procedural other`, not null default `"other"`.
- `VoteClassifier.classify(question :: String.t() | nil) :: String.t()`, case-insensitive, first match:
  1. `cloture` → `cloture`
  2. `nomination` → `nomination`
  3. `amendment` → `amendment`
  4. `motion to proceed|table|recommit|reconsider|discharge|previous question|quorum|adjourn|waive|point of order|instruct` → `procedural`
  5. `passage|pass|on the bill|joint resolution|concurrent resolution|resolution|conference report|veto` → `passage`
  6. otherwise `other`
- `Votes.reclassify([{vote_id, classification}]) :: :ok`.

Steps:
- [ ] Tests:
  - Each rule with real questions: "On Passage", "On Motion to Suspend the Rules and Pass" (passage); "On the Cloture Motion"; "On the Nomination"; "On Agreeing to the Amendment"; "On the Motion to Proceed", "On Ordering the Previous Question", "On Motion to Recommit" (procedural); "On the Joint Resolution" (passage); "Election of the Speaker" (other); nil → other.
  - Both normalizers set it.
  - The writer stores it.
  - The `reclassify_votes` job updates stored votes from their stored `question`.
- [ ] Run; FAIL. Implement. DECISIONS entry. Commit `feat: votes carry a normalized type`.

### Task 5: Bill text split into sections

**Files:** Migration `…_add_bill_version_sections.exs` (`bill_versions.sections` jsonb null); Modify `lib/the_floor/adapters/federal/xml_text.ex` (add `sections/1`), `lib/the_floor/ingest/records.ex` (`BillVersionText.sections`), writer, `sync_bill_text.ex`, `bulk_bill_text_chunk.ex`; Create `lib/the_floor/adapters/federal/jobs/backfill_bill_sections.ex` (on demand); Modify `lib/the_floor/legislation/bill_version.ex`.

**Interfaces:**
- `XmlText.sections(xml :: binary()) :: {:ok, [section()]} | {:error, term()}` where `section() :: %{"enum" => String.t() | nil, "heading" => String.t() | nil, "blocks" => [%{"level" => non_neg_integer(), "enum" => String.t() | nil, "heading" => String.t() | nil, "text" => String.t()}]}`.
  - Every `<section>` in document order, including those inside `<title>`/`<subtitle>`. Each title gets a `%{"kind" => "title"}` entry before its sections.
  - Blocks flatten `subsection`/`paragraph`/`subparagraph`/`clause`/`subclause` with `level` 0–4 and their `enum`, `header` and `text`, keeping quoted-block text inline.
  - Works for the bill DTD (`fixtures/govinfo/BILLS-119hr22ih.xml`) and USLM (`uslm_sample.xml`).
- Stored on `bill_versions.sections` (JSON list) whenever text is stored. `BackfillBillSections` processes 500 versions with XML and nil sections per run and re-enqueues itself until none remain.

Steps:
- [ ] Tests on the hr22 fixture:
  - First section `"enum" => "1."`, heading "Short title".
  - Section count equals the number of `<section>` elements.
  - Nested levels for a known subsection.
  - The USLM fixture parses.
  - `malformed.xml` → `{:error, _}`.
  - `SyncBillText` and a text chunk store sections.
  - The backfill fills them and re-enqueues until done.
- [ ] Run; FAIL. Implement with Saxy simple form. DECISIONS entry. Commit `feat: bill text sections parsed and stored`.

### Task 6: Address to reps

**Files:**
- Create `lib/the_floor/reps.ex`, the behaviour `lib/the_floor/reps/locator.ex`, and `lib/the_floor/adapters/federal/geocoder.ex`.
- Modify `config/config.exs` (`config :the_floor, :default_jurisdiction, "federal"`, `config :the_floor, :locators, %{"federal" => TheFloor.Adapters.Federal.Geocoder}`, `config :the_floor, :federal, census_vintages: %{119 => "ACS2025_Current"}`, rate limiter `census: 1000`) and `lib/the_floor/legislature.ex`.
- Fixtures: `test/support/fixtures/federal/census/iowa_city.json` (live capture for "400 S Clinton St, Iowa City, IA 52240", vintage ACS2025_Current), `dc.json` (1600 Pennsylvania Ave NW, Washington, DC 20500), `no_match.json`.

**Interfaces:**
- `TheFloor.Reps.Locator` callback `locate(address :: String.t()) :: {:ok, [{body_external_id :: String.t(), district :: String.t()}]} | {:error, :not_found | :unavailable}`.
- Federal geocoder:
  - Calls `https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress` with `benchmark=Public_AR_Current`, `vintage` = `census_vintages[congress]`, `format=json`, via `Federal.HTTP` and limiter `:census`.
  - Takes the layer named `"#{congress}th Congressional Districts"` (119 → "119th") and the `States` layer's `STUSAB`.
  - Returns `[{"house", "IA-1"}, {"senate", "IA"}]`. A district code of `00` or `98` → `"#{st}-AL"`. Places with no senators (DC, territories) still return `{"senate", st}`, which simply matches nobody.
- `Legislature.current_members(jurisdiction_key, [{body_external_id, district}], on :: Date.t()) :: [%{person: Person.t(), membership: Membership.t(), body: Body.t()}]`. Memberships current on `on`, where `district` equals the stored value, ordered with district-less bodies (statewide) first, then by person name.
- `TheFloor.Reps.find(address) :: {:ok, district_key :: String.t(), [rep]} | {:error, :not_found | :unavailable}`, where `district_key` is the narrowest returned district (`"IA-1"`). `TheFloor.Reps.for_district(district_key) :: [rep]` rebuilds the pairs through the locator module's `districts_for(district_key) :: [{body, district}]` (federal: `"IA-1"` → `[{"house","IA-1"},{"senate","IA"}]`).

Steps:
- [ ] Tests:
  - Iowa City fixture → `{"house","IA-1"}` and `{"senate","IA"}`.
  - The DC fixture → `"DC-AL"`.
  - No match → `:not_found`.
  - HTTP 500 → `:unavailable`.
  - `Reps.find/1` with stored Iowa members returns 2 senators first, then the representative.
  - DC returns only the delegate.
  - A senator whose membership ended is excluded.
- [ ] Run; FAIL. Implement. Commit `feat: find your reps from an address`.

### Task 7: Activity feed read model

**Files:** Create `lib/the_floor/activity.ex`, `lib/the_floor/activity/item.ex`; Test `test/the_floor/activity_test.exs`

**Interfaces:**
- `%Activity.Item{kind: :vote | :introduced | :moved | :became_law, date: Date.t(), bill: Bill.t() | nil, vote: Vote.t() | nil, option: String.t() | nil, action: BillAction.t() | nil}`.
- `Activity.feed(person_id, opts) :: %{items: [Item.t()], next: cursor | nil}`.
  - opts: `filter: :all | :votes | :bills | :law` (default `:all`), `before: cursor`, `limit` (default 25).
  - The cursor is opaque, encoding `{date, kind_rank, id}`.
  - Newest first; ties ordered became_law, moved, introduced, vote.
- Sources for each kind:
  - Votes: the person's positions (date = `voted_at` in America/New_York).
  - Introduced: primary sponsorships (date = sponsorship date).
  - Moved: actions on bills they sponsored with classification in `reported scheduled passed_chamber enrolled signed`.
  - Became law: `became_law`.
- `Activity.counts(person_id) :: %{sponsored: n, cosponsored: n}`.

Steps:
- [ ] Tests over a seeded person:
  - All kinds appear in order.
  - Each filter returns only its kinds.
  - A cosponsored bill does not appear.
  - `referred` actions do not appear.
  - Pagination with `limit: 2` walks every item exactly once.
  - Counts.
  - A person with nothing → `items: []`.
- [ ] Run; FAIL. Implement as one `union_all` query per page over the three sources. Commit `feat: rep activity feed`.

### Task 8: Home, reps and rep page (LiveView)

**Files:**
- Modify `lib/the_floor_web/router.ex` and `lib/the_floor_web/components/layouts.ex` (app shell: header "The Floor" plus a "Change address" link), and `assets/css/app.css` (tokens from Global Constraints, Public Sans via `<link>` in root layout).
- Create `lib/the_floor_web/components/floor_components.ex`: `vote_chip/1` (`option`), `card/1`, `section_heading/1`, `source_line/1`.
- Create `lib/the_floor_web/controllers/district_controller.ex`, `lib/the_floor_web/live/home_live.ex` and `lib/the_floor_web/live/reps_live.ex`.
- Delete the generated page controller and home template.

**Interfaces / routes:**
- `GET /` → `HomeLive`: the address form (label "Your address"). It submits by `phx-trigger-action` to `POST /district`.
- `POST /district` → `DistrictController.create`: calls `Reps.find/1`, puts `district` in the session, and redirects to `/reps/:district`. On error it re-renders the form with the message (Review Focus 1) and the typed address.
- `GET /reps/:district` → `RepsLive`: params `rep` (person id, default the first rep) and `filter` (`all votes bills law`). It renders mockup board A:
  - the rep row
  - the header with counts
  - filter links (patch)
  - the feed grouped by day, with each item linking to `/bills/:external_id`
  - "Load more" (the cursor)
  - a "What it would change" box with `latest_summary` HTML for `:moved`/`:became_law` items
  - the source line
- A visitor with `district` in the session who opens `/` is offered "Your reps (IA-1)".

Steps:
- [ ] LiveView tests (`Phoenix.LiveViewTest`):
  - The form posts and redirects to `/reps/IA-1` with the Census request stubbed.
  - A not-found address shows the message and keeps the input.
  - The reps page shows three reps, with the selected one marked `aria-pressed="true"`.
  - Switching `rep` patches.
  - The `votes` filter shows only vote items with "Voted Yea".
  - An empty feed shows "Nothing yet" (Review Focus 5).
  - A bill link goes to `/bills/119-s-4668`.
  - The address never appears in the rendered page or the redirect URL.
- [ ] Run; FAIL. Implement. Commit `feat: home and rep pages`.

### Task 9: Bill page

**Files:** Create `lib/the_floor_web/live/bill_live.ex`, `lib/the_floor/bill_page.ex`; Tests.

**Interfaces:**
- `TheFloor.BillPage.load(jurisdiction_key, external_id, viewer_person_ids :: [integer()]) :: {:ok, page} | :not_found`. `page` carries the following.
  - `bill`, `sponsor`, `cosponsor_count`.
  - `steps`, a list of `%{label, date, state: :done | :current | :todo}`:
    - Bills and joint resolutions: Introduced, Committee, first chamber passed, second chamber passed, Law. Labels come from the body names of `from_body` and the other chamber.
    - Simple resolutions (classification `resolution`): Introduced, Committee, Agreed to.
    - Concurrent resolutions: Introduced, Committee, first chamber, second chamber, Agreed to.
    - Done-ness comes from action classifications (`reported`, `passed_chamber` per actor body, `became_law`).
  - `latest_action`.
  - `reps`: for each viewer rep, `%{person, option | :sponsor | :cosponsor | :no_vote | :not_in_office}`, from `Votes.main_vote(bill, body)` (passage in that body, else that body's latest roll call).
  - `summary` (latest), `versions` (newest first, with `sections`), `votes` (newest first).
- `GET /bills/:id` → `BillLive`, with params `version` (code, default newest) and `section` (open section enum). It renders the "Bill page (M2)" board. The open section shows its blocks indented by level, with an empty, labeled slot reserved above the text for later summaries (not rendered in M2: a comment and a CSS class only). "Back" goes to the referring rep page when `from` is given.

Steps:
- [ ] Tests:
  - Status steps for a bill passed by one chamber, a law, a simple resolution ("Agreed to", no Law step, Review Focus 3) and a bill that was only referred.
  - `reps` options for a senator who voted, a representative whose chamber has not voted, and the sponsor.
  - Picking a version changes the sections.
  - Missing summary, text or votes each show their one-line message (Review Focus 4).
  - An unknown id gives 404.
  - The official-record link uses the stored source URL.
- [ ] Run; FAIL. Implement. Commit `feat: bill page`.

### Task 10: This week

**Files:** Create `lib/the_floor_web/live/this_week_live.ex`; Modify `lib/the_floor/calendar.ex`.

**Interfaces:**
- `Calendar.week(jurisdiction_key, from :: Date.t(), opts) :: [%{date, events: [Event.t() with body and bills]}]`, covering the 7 days from `from` (America/New_York).
  - `opts[:people]` (person ids) narrows to events on bills those people sponsored or cosponsored, or held by committees where they hold a current membership.
  - Events with `unresolved_bill_labels` are kept, and their labels are shown unlinked.
- `GET /this-week` → `ThisWeekLive`: a "My reps" toggle when the session has a district, events grouped by day, each with its time, body name, title and linked bills.

Steps:
- [ ] Tests:
  - Events outside the 7 days are excluded.
  - The people filter keeps a committee meeting of a member's committee and a floor item on a cosponsored bill.
  - Unresolved labels render as text.
  - An empty week says "Nothing scheduled".
- [ ] Run; FAIL. Implement; link "This week" in the app header. Commit `feat: this week view`.

### Task 11: Ship it

- [ ] Run on production via `TheFloor.Release.ingest/1`: `bill_summaries`, `reclassify_votes`, `bill_sections`, then `TheFloor.Release.reclassify_actions()`. Check counts: bills with a summary, votes with a non-`other` type, versions with sections.
- [ ] Manual check on a phone: Iowa City address → reps → Grassley → S. 4668 → this week.
- [ ] README (routes, the on-demand jobs), DECISIONS entries done in tasks, CLAUDE.md "Current milestone" → M2b next. Commit `docs: M2a shipped`.
