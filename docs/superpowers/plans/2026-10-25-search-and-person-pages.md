# Search and Person Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A search box on every page that finds bills by number, by any of their names and by words in their text, and finds people by name or place. A page for every person. Every person named on a bill page links to that page.

**Architecture:**
- The federal adapter fetches every title a bill has into a new `bill_titles` table. A one-off backfill job fills it for stored bills.
- A new jurisdiction-neutral `EverydayCitizen.Search` context runs the searches in Postgres:
  - a key on bill identifiers;
  - `pg_trgm` on title and name keys, through one SQL function, `ec_name_key`;
  - a GIN full-text index on `bill_versions.plain_text`.
- Place names and district labels come from two new callbacks on the existing `Reps.Locator` behaviour, which the federal `Geocoder` implements.
- On the web side:
  - a POST-only search form in the layout, with a controller that classifies the query and redirects;
  - a `SearchLive` results page;
  - a `PersonLive` page built on a rep panel extracted from `RepsLive`.

**Tech Stack:** Elixir 1.20, Phoenix 1.8 LiveView, Ecto/PostgreSQL (`pg_trgm`, `tsvector`), Oban, Req with Req.Test.

**Spec:** `docs/superpowers/specs/2026-10-25-search-and-person-pages-design.md`. Read its "Details settled before planning" section too. Mockup: https://claude.ai/artifact/V8QwBjvAvvo35JGv3XYDmq

## Global Constraints

- No UI or domain code knows it is federal. `test/everyday_citizen/boundary_test.exs` rejects any `lib/**/*.ex` file outside `lib/everyday_citizen/adapters/federal/` containing `congress`, `bioguide`, `senate`, `house`, `lis_member` or `crs` as words, comments and HEEx included. Chamber names in copy come from `body.name` data.
- UI copy never names a legislature.
- Every stored record carries provenance (`source_id` → source URL, `fetched_at`, content hash).
- Search never starts an AI summary. It shows only summaries already cached (`Summaries.get_ai/3`).
- Crawlers never start one either (`EverydayCitizenWeb.Crawler`). Search pages are `noindex`; person pages are indexed.
- Addresses and ZIP codes are never stored, logged or put in a URL.
- Tests never call outside services. HTTP goes through `:federal_req_options` and Req.Test (`no_network_test.exs`).
- Everything this work adds to the database stays under 500 MB in total. A probe on the dev copy measured the full-text GIN index at 21 MB over 23,037 versions.
- Phone width first: every new page works at about 400px wide, as in the mockup.
- Before each commit, run `mix precommit` and `mix credo --strict`. Use the commit trailer lines from the session (Co-Authored-By, Claude-Session).
- Never run `mix ecto.reset` or `mix ecto.drop`. Use `mix ecto.migrate` only.
- Ranking never uses a notion of "famous" or "controversial". It uses only name tier, the furthest stage reached, and date.

## Review Focus

1. **Two-letter everyday words that are also postal codes.** "in", "or", "me", "ok" and "hi" must not turn into state results. Postal codes count only when typed in capitals ("OH"); full state names count in any case. Tested in Task 5.
2. **Punctuation and operators in queries.** Quotes, `&`, `:`, `'`, `!`, `-` and parentheses must neither crash the text search nor raise a tsquery syntax error. `websearch_to_tsquery` is used everywhere. Tested in Task 4.
3. **Markup in bill text.** Bill text containing `<`, `&` or `<script>` must come out escaped in an excerpt. Only the highlight becomes `<mark>`. Tested in Task 4.
4. **An address typed into the search box, including by URL.** `/search?q=123 Main St` typed by hand must show the "looks like an address" message, run no search, and carry the query into no link. Tested in Task 7.
5. **A person no longer in office.** Their page must render their last chamber role, open on their most recent active week, and not crash on a missing current membership. Tested in Task 6.

---

### Task 1: Store every title a bill has

**Files:**
- Create: `priv/repo/migrations/20261025100000_create_bill_titles_and_search_keys.exs`
- Create: `lib/everyday_citizen/legislation/bill_title.ex`
- Modify: `lib/everyday_citizen/ingest/records.ex` (add `BillTitles`)
- Modify: `lib/everyday_citizen/ingest.ex` (dispatch `BillTitles` to `Writer.Legislation`)
- Modify: `lib/everyday_citizen/ingest/writer/legislation.ex` (a `do_write` clause using `replace_set`)
- Modify: `lib/everyday_citizen/adapters/federal/normalize/bill_context.ex` (`titles/3`)
- Modify: `lib/everyday_citizen/adapters/federal/bill_writer.ex` (optional `:titles` part, written in `write_context`)
- Modify: `lib/everyday_citizen/adapters/federal/jobs/sync_bill.ex` (fetch `base <> "/titles"` with `fetch_all(…, "titles")`)
- Fixtures (already captured from the live API, committed with the plan): `test/support/fixtures/federal/congress_gov/bill_119_hr_1/titles.json`, `bill_119_hr_22/titles.json`, `bill_119_hr_7008/titles.json`
- Test: `test/everyday_citizen/adapters/federal/normalize/bill_context_test.exs`, `test/everyday_citizen/adapters/federal/jobs/sync_bill_test.exs`, `test/everyday_citizen/ingest/bill_titles_writer_test.exs`

**Interfaces:**
- Produces:
  - table `bill_titles(id, bill_id → bills on delete cascade, title text not null, kind varchar not null, source_id → sources, timestamps)`, with index on `bill_id`;
  - SQL function `ec_name_key(text) returns text`, `IMMUTABLE`, `PARALLEL SAFE`;
  - trigram GIN indexes on `ec_name_key(bill_titles.title)`, `ec_name_key(bills.title)` and `ec_name_key(people.name)`;
  - `CREATE EXTENSION IF NOT EXISTS pg_trgm`.
- Produces: `%Records.BillTitles{jurisdiction, bill_external_id, titles: [%{title: String.t(), kind: String.t()}], source}`. It replaces the bill's stored set.
- Produces: `Normalize.BillContext.titles(items :: [map()], bill_external_id :: String.t(), SourceRef.t()) :: Records.BillTitles.t()`.

`ec_name_key` is the one rule for comparing names, used in SQL and mirrored in Elixir by Task 3:
1. Lower-case the text.
2. Replace every run of characters that aren't letters or digits with one space.
3. Trim.
4. Strip a trailing ` of <4 digits>`.
5. Strip a trailing ` act`.
6. Trim again.

Write it as a plain `LANGUAGE sql` function using `regexp_replace`. Example: `'SAVE Act'` → `'save'`; `'Laken Riley Act of 2025'` → `'laken riley'`; `'One Big Beautiful Bill Act'` → `'one big beautiful bill'`.

How title kinds map from Congress.gov `titleType`, checked in this order:
1. Contains "for portions" → `part`.
2. Contains "Popular" → `popular`.
3. Contains "Short Title" → `short`.
4. Contains "Official Title" → `official`.
5. "Display Title" and "Override Display Title" → dropped, because `bills.title` already holds it.

Deduplicate on `{kind, title}`. Ruling for the ledger: the spec names three kinds. `part` is a fourth, because H.R. 1 carries titles of its parts ("FEHB Protection Act of 2025"). Those are searchable but rank in the same tiers. Cost if wrong: one mapping line.

- [ ] **Step 1: Write the failing tests**

```elixir
# bill_context_test.exs
test "titles keeps official, short, popular and part titles, drops display ones, dedupes" do
  items = fixture("bill_119_hr_1/titles.json")["titles"]
  r = BillContext.titles(items, "119-hr-1", src())
  assert %{title: "One Big Beautiful Bill Act", kind: "popular"} in r.titles
  assert %{title: "One Big Beautiful Bill Act", kind: "short"} in r.titles
  assert %{title: "FEHB Protection Act of 2025", kind: "part"} in r.titles
  assert Enum.any?(r.titles, &(&1.kind == "official"))
  assert r.titles == Enum.uniq(r.titles)
  refute Enum.any?(r.titles, &(&1.kind not in ~w(official short popular part)))
end

# bill_titles_writer_test.exs
test "writing BillTitles replaces the bill's set" do
  # write a bill, then titles [a, b], then titles [b]
  assert titles_of(bill) == ["b"]
end

test "ec_name_key normalizes names" do
  for {input, key} <- [{"SAVE Act", "save"}, {"Laken Riley Act of 2025", "laken riley"},
                       {"One Big Beautiful Bill Act", "one big beautiful bill"},
                       {"  H.R. 22 — the SAVE act!", "h r 22 the save"}] do
    assert Repo.query!("select ec_name_key($1)", [input]).rows == [[key]]
  end
end

# sync_bill_test.exs: add "/v3/bill/119/hr/22/titles" => "bill_119_hr_22/titles.json" to @fixtures
test "sync stores the bill's titles" do
  assert :ok = perform_job(SyncBill, %{"congress" => 119, "type" => "HR", "number" => "22"})
  assert "Safeguard American Voter Eligibility Act" in Repo.all(from t in BillTitle, select: t.title)
end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/everyday_citizen/adapters/federal/normalize/bill_context_test.exs test/everyday_citizen/ingest/bill_titles_writer_test.exs test/everyday_citizen/adapters/federal/jobs/sync_bill_test.exs`
Expected: FAIL. `titles/3` is undefined, `ec_name_key` does not exist, and the stub raises on the unknown path `/titles` until the fixture map has it.

- [ ] **Step 3: Implement**

Write the migration, schema, record, writer clause, normalizer and sync change described above. In `BillWriter.write_context`, add `{Map.get(parts, :titles, {[], nil}), &BillContext.titles(&1, id, &2)}` to the list, so an empty list writes nothing, as the other parts do. Any other test file that stubs `SyncBill` paths, such as `full_ingest_test.exs`, also needs a `/titles` fixture entry. Use `bill_119_hr_7008/titles.json` for H.R. 7008.

- [ ] **Step 4: Run them and the full suite**

Run: `mix test`
Expected: PASS, with `boundary_test.exs` green.

- [ ] **Step 5: Commit**

`git commit -m "feat: store every title a bill has"`

---

### Task 2: Backfill titles for stored bills

**Files:**
- Create: `lib/everyday_citizen/adapters/federal/jobs/sync_bill_titles.ex`
- Create: `lib/everyday_citizen/adapters/federal/jobs/backfill_bill_titles.ex`
- Modify: `lib/everyday_citizen/adapters/federal/jobs.ex` (add `{"bill_titles", BackfillBillTitles, %{}}` to `on_demand/0`)
- Modify: `lib/everyday_citizen/legislation.ex` (`bill_external_ids/1`)
- Modify: `config/config.exs` (Oban queues: add `backfill: 1`)
- Test: `test/everyday_citizen/adapters/federal/jobs/backfill_bill_titles_test.exs`

**Interfaces:**
- Consumes: `BillContext.titles/3` and `Records.BillTitles` from Task 1.
- Produces: `SyncBillTitles`, an Oban worker on queue `:backfill`, `max_attempts: 5`, unique per `[:congress, :type, :number]` for 3600s. It takes args `%{"congress", "type", "number"}`, makes one `CongressGov.paginate(base <> "/titles", "titles")` call through `fetch_all`, and runs `Ingest.write`. A 404 means the bill was removed upstream and returns `:ok`.
- Produces: `BackfillBillTitles` on queue `:ingest`. It runs through `Job.run("backfill_bill_titles", …)` and inserts one `SyncBillTitles` per stored federal bill with `Oban.insert_all` in chunks of 1,000. It returns `{:ok, %{"enqueued" => n}}`.
- Produces: `Legislation.bill_external_ids(jurisdiction_key :: String.t()) :: [String.t()]`.

The backfill doesn't starve the nightly jobs because the `backfill` queue runs one job at a time. Meanwhile `ingest` runs 4, and every request shares the `:congress_gov` limiter (750 ms, first come first served). Nightly work therefore gets about four of every five requests while both are busy. Ruling for the ledger: no change to the limiter. Cost if wrong: a slower nightly run during the one-off backfill.

- [ ] **Step 1: Write the failing tests**

```elixir
test "backfill enqueues one titles job per stored bill on the backfill queue" do
  # two bills stored
  assert {:ok, %{"enqueued" => 2}} = perform_job(BackfillBillTitles, %{})
  assert_enqueued worker: SyncBillTitles, queue: :backfill, args: %{"congress" => 119, "type" => "hr", "number" => "22"}
end

test "a titles job writes the titles" do
  stub_titles("/v3/bill/119/hr/22/titles", "bill_119_hr_22/titles.json")
  assert :ok = perform_job(SyncBillTitles, %{"congress" => 119, "type" => "hr", "number" => "22"})
  assert "SAVE Act" in titles_of("119-hr-22")
end

test "a titles job for a bill the source no longer has is done, not retried" do
  stub_status("/v3/bill/119/hr/22/titles", 404)
  assert :ok = perform_job(SyncBillTitles, %{"congress" => 119, "type" => "hr", "number" => "22"})
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen/adapters/federal/jobs/backfill_bill_titles_test.exs`
Expected: FAIL, with the modules undefined.

- [ ] **Step 3: Implement the two workers, `bill_external_ids/1`, the queue and the on-demand entry**

- [ ] **Step 4: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat: backfill every stored bill's titles"`

---

### Task 3: Classify what someone typed

**Files:**
- Create: `lib/everyday_citizen/search/query.ex`
- Test: `test/everyday_citizen/search/query_test.exs`

**Interfaces:**
- Produces: `EverydayCitizen.Search.Query.classify(raw :: String.t() | nil) :: :empty | :address | {:search, %Query{text: String.t(), key: String.t(), id_key: String.t() | nil, number: String.t() | nil}}`
  - `text` is the trimmed query, with inner whitespace collapsed and at most 200 characters.
  - `key` is the Elixir mirror of `ec_name_key` from Task 1.
  - `id_key` is the lower-case query with everything but letters and digits removed, set only when that matches `^[a-z]{1,8}\d{1,5}$` (for example "hr22", "hres1131", "s5").
  - `number` is set when the query is only digits, 1 to 5 of them.
- Produces: `Query.name_key(String.t()) :: String.t()`, used by tests to check that it matches `ec_name_key`.

The address rule errs toward treating a query as an address. A query is `:address` when either of these holds:
- **It looks like a ZIP:** it matches `^\d{5}(-\d{4})?$`.
- **It looks like a street address:** it matches `^\d{1,6}[a-z]?\s+\S` (case-insensitive), and it contains a comma or a street word as a whole word. The street words are: st, street, ave, avenue, rd, road, dr, drive, ln, lane, blvd, boulevard, way, ct, court, pl, place, hwy, highway, pkwy, parkway, cir, circle, ter, terrace, trl, trail, pike, apt, unit, suite, ste, box, route, rte. A query is also an address when it matches `^\d{1,6}\s+(n|s|e|w|north|south|east|west)\s` (case-insensitive).

A query that is empty, or shorter than 2 characters after trimming, is `:empty`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "addresses and ZIP codes are recognized" do
  for q <- ["43215", "43215-1234", "123 Main St", "1600 Pennsylvania Avenue NW, Washington",
            "12 N High", "4B Elm Court", "77 Route 9"],
      do: assert(Query.classify(q) == :address, q)
end

test "bill numbers, names, phrases and bare numbers are searches" do
  assert {:search, %{id_key: "hr22"}} = Query.classify("H.R. 22")
  assert {:search, %{id_key: "hr22"}} = Query.classify("hr22")
  assert {:search, %{id_key: nil, key: "save"}} = Query.classify("SAVE Act")
  assert {:search, %{number: "22", id_key: nil}} = Query.classify("22")
  assert {:search, %{text: "22 states"}} = Query.classify(" 22   states ")
  assert {:search, %{text: "daylight saving time"}} = Query.classify("daylight saving time")
end

test "empty and one-character queries are empty" do
  for q <- [nil, "", "   ", "a"], do: assert(Query.classify(q) == :empty)
end

test "the Elixir name key matches the database's" do
  for s <- ["SAVE Act", "Laken Riley Act of 2025", "  H.R. 22 — the SAVE act!", "Ünïcode Act"] do
    assert Query.name_key(s) == hd(hd(Repo.query!("select ec_name_key($1)", [s]).rows))
  end
end
```

(The last test needs `DataCase`. Put it in its own `describe` with `use EverydayCitizen.DataCase`, or in a second test module.)

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen/search/query_test.exs`
Expected: FAIL, with `Query` undefined.

- [ ] **Step 3: Implement `Query`**

Use Unicode-aware regexes (`~r/[^\p{L}\p{N}]+/u`) on both sides, so `ec_name_key` and `name_key` agree. If Postgres's `[^[:alnum:]]` treats letters with accents differently, change the migration's function to match, in a new migration. Never edit a migration that has already run.

- [ ] **Step 4: Run and pass**

Run: `mix test test/everyday_citizen/search/query_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat: classify search queries, recognizing addresses"`

---

### Task 4: Search bills by number, name and text

**Files:**
- Create: `priv/repo/migrations/20261025110000_add_bill_search_indexes.exs`
- Create: `lib/everyday_citizen/search.ex`
- Create: `lib/everyday_citizen/search/excerpt.ex`
- Test: `test/everyday_citizen/search_bills_test.exs`, `test/everyday_citizen/search/excerpt_test.exs`

**Interfaces:**
- Consumes: `Query` from Task 3, and `bill_titles` and `ec_name_key` from Task 1.
- Produces:
  - `Search.bill_by_number(Query.t()) :: {:one, Bill.t()} | {:many, [Bill.t()]} | :none`. It matches `id_key` against the identifier key across all sessions. A bare `number` matches every bill type with that number, and always returns `{:many, …}` or `:none`.
  - `Search.bills_by_name(Query.t(), limit :: pos_integer()) :: [%{bill: Bill.t(), title: String.t(), stage: atom(), summary: String.t() | nil}]`. `title` is the title that matched, and `summary` is the cached AI bill summary text, if any.
  - `Search.bills_by_text(Query.t(), exclude_bill_ids :: [integer()], page :: pos_integer()) :: %{results: [%{bill: Bill.t(), excerpt: Excerpt.t() | nil, stage: atom()}], total: non_neg_integer(), more?: boolean()}`. It returns 10 results per page, and `total` is capped at 1,000.
  - `Search.Excerpt.t() :: %{section: String.t() | nil, parts: [{:text | :mark, String.t()}]}`.
- Produces: `Search.stage(bill_id)` is internal. Stage order, highest first: `:law` (any action classified `became_law` or `signed`), `:passed` (`passed_chamber`), `:voted` (any roll-call vote on the bill), `:reported` (`reported`), `:introduced`.

The migration:
- `create index bill_versions_text_search on bill_versions using gin (to_tsvector('english', plain_text)) where plain_text is not null`. Build it with `CREATE INDEX CONCURRENTLY` and `@disable_ddl_transaction true` plus `@disable_migration_lock true`, so production stays writable.
- An index on the identifier key: `lower(regexp_replace(identifier, '[^A-Za-z0-9]', '', 'g'))` on `bills`.

**Name ranking**, in this strict order:
- tier 1: `ec_name_key(title) = key`;
- tier 2: `ec_name_key(title) LIKE '%' || key || '%'`;
- tier 3: `ec_name_key(title) LIKE ALL (array of '%word%' for each word of key)`.

Then stage, highest first, then `introduced_on` newest first. Candidate titles are the union of `bill_titles.title` and `bills.title`. Each bill appears once, at its best tier, with the title that earned it. Escape `%`, `_` and `\` in key words before building `LIKE` patterns.

**Text query:**
- Use `websearch_to_tsquery('english', text)`. When it is empty (all stopwords or punctuation), skip the text group.
- The latest version per bill is the row with `plain_text` and the greatest `{date, id}` (`DISTINCT ON (bill_id) … ORDER BY bill_id, date DESC NULLS LAST, id DESC`). Filter to it after the indexed match, inside a `LIMIT 1000` subquery.
- Rank text results by stage, then `introduced_on` newest first. Don't use `ts_rank`: it would rebuild the tsvector of multi-MB bills.

**Excerpts**, built only for the results shown (`Excerpt.build(version_id, text)`):
1. Load that version's `sections`.
2. Among sections, walk the blocks and take the first block whose text matches `to_tsvector('english', block_text) @@ websearch_to_tsquery('english', text)`. Check the candidates in one SQL query over `jsonb_array_elements`, limited to that version.
3. Run `ts_headline('english', block_text, query, 'StartSel=<<<EC_MARK>>>, StopSel=<<<EC_END>>>, MaxWords=30, MinWords=12, MaxFragments=1')` on that block only.
4. Split the output on the markers into `{:text, …}` and `{:mark, …}` parts. HEEx escapes the text and renders only `:mark` parts as `<mark>`.
5. The `section` label is `"Sec. #{enum}"`, with the trailing dot trimmed from `enum`, followed by ` #{heading}` when a heading exists.
6. With no sections, or no matching block, fall back to `ts_headline` over `left(plain_text, 200000)`, with `section: nil`.

- [ ] **Step 1: Write the failing tests**

```elixir
# search_bills_test.exs (DataCase; build bills with Ingest.write like FloorFixtures)
test "a bill number finds that bill whatever the spacing" do
  for q <- ["H.R. 22", "hr22", "h.r.22"], do: assert {:one, %{external_id: "119-hr-22"}} = Search.bill_by_number(search(q))
end

test "a bare number lists every bill with that number" do
  assert {:many, bills} = Search.bill_by_number(search("22"))
  assert Enum.map(bills, & &1.identifier) |> Enum.sort() == ["H.R. 22", "S. 22"]
end

test "a popular name finds the bill stored under its formal title" do
  # bill 119-hr-1 with title "An act to provide for reconciliation…" and a popular title row
  assert [%{bill: %{external_id: "119-hr-1"}, title: "One Big Beautiful Bill Act"} | _] =
           Search.bills_by_name(search("big beautiful bill"), 10)
end

test "a whole-name match outranks a bill that only mentions the name" do
  # 119-hr-22 "SAVE Act" (introduced), 119-hr-5904 "To amend the SAVE Act ..." (passed)
  assert [%{bill: %{external_id: "119-hr-22"}} | _] = Search.bills_by_name(search("save act"), 10)
end

test "within a tier the bill that got further comes first" do
  # two bills both titled "SAVE Act": one with a passed_chamber action
  assert [%{stage: :passed}, %{stage: :introduced}] = Search.bills_by_name(search("SAVE Act"), 10)
end

test "a phrase finds bills whose latest text contains it, excluding name matches" do
  # bill A latest version mentions "daylight saving time"; bill A's older version does not matter;
  # bill B's only older version mentions it but its latest does not
  %{results: [r], total: 1} = Search.bills_by_text(search("daylight saving time"), [], 1)
  assert r.bill.external_id == "119-hr-100"
  assert %{results: []} = Search.bills_by_text(search("daylight saving time"), [r.bill.id], 1)
end

test "queries with punctuation and operators never raise" do
  for q <- [~s("save act"), "a & b", "tax: credit", "o'brien", "!!!", "(foo", "-x", "the of and"],
      do: assert %{results: _} = Search.bills_by_text(search(q), [], 1)
end

test "the cached AI summary rides along, and none is started" do
  # one cached :bill summary for 119-hr-22
  assert [%{summary: text}] = Search.bills_by_name(search("SAVE Act"), 1)
  assert text =~ "citizenship"
  refute_enqueued worker: EverydayCitizen.Jobs.SummarizeSubject
end

# excerpt_test.exs
test "an excerpt names the section and marks the match" do
  # version with sections [section("1.", "Short title", ["This Act may be cited..."]),
  #                        section("4.", "Clocks", ["Daylight saving time shall be permanent."])]
  assert %{section: "Sec. 4 Clocks", parts: parts} = Excerpt.build(version.id, "daylight saving time")
  assert {:mark, "Daylight"} in parts
end

test "bill text markup comes out as text, not HTML" do
  # block text: "Section <script>alert(1)</script> & daylight rules"
  %{parts: parts} = Excerpt.build(version.id, "daylight")
  assert Enum.any?(parts, fn {:text, t} -> t =~ "<script>"; _ -> false end)
end

test "a version without sections still gets an excerpt with no section label" do
  assert %{section: nil, parts: [_ | _]} = Excerpt.build(plain_only.id, "daylight")
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen/search_bills_test.exs test/everyday_citizen/search/excerpt_test.exs`
Expected: FAIL, with `Search` undefined.

- [ ] **Step 3: Write the migration and run it on dev; measure**

Run: `mix ecto.migrate && psql the_floor_dev -Atc "select pg_size_pretty(pg_relation_size('bill_versions_text_search'))"`
Expected: about 21 MB. Record the number in the ledger.

- [ ] **Step 4: Implement `Search` bill functions and `Excerpt`**

- [ ] **Step 5: Run the tests, then time one real query on dev**

Run: `mix test test/everyday_citizen/search_bills_test.exs test/everyday_citizen/search/excerpt_test.exs`
Expected: PASS.

Then run `Search.bills_by_text` for "daylight saving time" and for "the", in `iex -S mix` against dev.
Expected: each returns in under 1 second. Record the timings in the ledger.

- [ ] **Step 6: Commit**

`git commit -m "feat: search bills by number, name and text"`

---

### Task 5: Search people by name and by place

**Files:**
- Modify: `lib/everyday_citizen/reps/locator.ex` (two callbacks)
- Modify: `lib/everyday_citizen/adapters/federal/geocoder.ex` (implement them)
- Create: `lib/everyday_citizen/adapters/federal/states.ex`. It covers the 50 states, DC, and the territories AS, GU, MP, PR and VI. Each entry is code, name and possessive name.
- Modify: `lib/everyday_citizen/reps.ex` (`place/1`, `district_label/1`)
- Modify: `lib/everyday_citizen/legislature.ex` (`current_members_matching/3`)
- Modify: `lib/everyday_citizen/search.ex` (`people/2`)
- Test: `test/everyday_citizen/adapters/federal/geocoder_test.exs`, `test/everyday_citizen/reps_test.exs`, `test/everyday_citizen/search_people_test.exs`

**Interfaces:**
- Produces callbacks on `Reps.Locator`:
  - `@callback place(query :: String.t()) :: {:ok, %{name: String.t(), seats: [{body_external_id :: String.t(), {:exact | :prefix, String.t()}}]}} | :error`. Body order is the order results are listed in.
  - `@callback district_label(district :: String.t()) :: String.t()`.
- Federal `place/1`:
  - It matches a full state name in any case after trimming, or a postal code only when typed in capitals.
  - It returns `seats: [{"senate", {:exact, code}}, {"house", {:prefix, code <> "-"}}]`.
  - DC and the territories have no senate seat.
- Federal `district_label/1`:
  - `"OH-4"` → `"Ohio's 4th district"`; `"AK-AL"` → `"Alaska at large"`; `"OH"` → `"Ohio"`.
  - Ordinals are 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st, 22nd and so on.
  - An unknown key returns the key itself.
- Produces:
  - `Reps.place(query) :: nil | %{name: String.t(), reps: [Reps.rep()]}`.
  - `Reps.district_label(district :: String.t() | nil) :: String.t() | nil`. It returns nil for nil.
- Produces: `Legislature.current_members_matching(jurisdiction_key, seats_with_matchers, on :: Date.t()) :: [Reps.rep()]`. Results come in seat order, then in natural district order within a seat ("OH-2" before "OH-10", by the trailing integer), then by name.
- Produces: `Search.people(Query.t(), limit) :: %{place: nil | %{name: String.t(), reps: [Reps.rep()]}, people: [%{person: Person.t(), membership: Membership.t() | nil, body: Body.t() | nil}]}`.
  - Name matches use `ec_name_key(people.name)`. The tiers:
    1. equality;
    2. `LIKE '%key%'`;
    3. `word_similarity(key, ec_name_key(name)) >= 0.5`, for small typos.
  - Within a tier, people currently in office come first, then by name.
  - Each person carries their latest chamber membership: the body with classification `"chamber"`, latest `start_date`.
  - People already listed under the place are left out of `people`.

- [ ] **Step 1: Write the failing tests**

```elixir
# geocoder_test.exs
test "place matches full state names in any case and postal codes only in capitals" do
  assert {:ok, %{name: "Ohio", seats: [{"senate", {:exact, "OH"}}, {"house", {:prefix, "OH-"}}]}} = Geocoder.place("ohio")
  assert {:ok, %{name: "Ohio"}} = Geocoder.place("OH")
  for q <- ["in", "or", "me", "ok", "hi", "oh"], do: assert(Geocoder.place(q) == :error, q)
  assert {:ok, %{name: "Indiana"}} = Geocoder.place("IN")
  assert {:ok, %{name: "District of Columbia", seats: [{"house", {:prefix, "DC-"}}]}} = Geocoder.place("district of columbia")
end

test "district labels" do
  assert Geocoder.district_label("OH-4") == "Ohio's 4th district"
  assert Geocoder.district_label("NY-12") == "New York's 12th district"
  assert Geocoder.district_label("TX-22") == "Texas's 22nd district"
  assert Geocoder.district_label("AK-AL") == "Alaska at large"
  assert Geocoder.district_label("IA") == "Iowa"
  assert Geocoder.district_label("ZZ-9") == "ZZ-9"
end

# search_people_test.exs (FloorFixtures.iowa! plus a former member and IA-2, IA-10 seats)
test "a state lists its senators, then its House members in district order" do
  %{place: %{name: "Iowa", reps: reps}} = Search.people(search("iowa"), 20)
  assert Enum.map(reps, & &1.membership.district) == ["IA", "IA", "IA-1", "IA-2", "IA-10"]
end

test "a name finds the person, tolerating a small typo" do
  assert %{people: [%{person: %{name: "Joni Ernst"}} | _]} = Search.people(search("Joni Ernst"), 10)
  assert %{people: [%{person: %{name: "Chuck Grassley"}} | _]} = Search.people(search("chuck grasley"), 10)
end

test "former members are found too, after those in office" do
  # "Joni Ernstly" ended 2023
  assert [%{person: %{name: "Joni Ernst"}}, %{person: %{name: "Joni Ernstly"}}] =
           Search.people(search("joni"), 10).people
end

test "a query naming a place and a person shows both" do
  # a person named "Iowa Smith"
  %{place: %{name: "Iowa"}, people: [%{person: %{name: "Iowa Smith"}}]} = Search.people(search("iowa"), 10)
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen/adapters/federal/geocoder_test.exs test/everyday_citizen/search_people_test.exs test/everyday_citizen/reps_test.exs`
Expected: FAIL, with the functions undefined.

- [ ] **Step 3: Implement**

Write the callbacks, the federal implementation with `States`, the `Reps` wrappers through `locator()`, `current_members_matching/3` and `Search.people/2`. Test locators in `test/support`, if any implement `Reps.Locator`, need the two new callbacks too.

- [ ] **Step 4: Run the full suite**

Run: `mix test`
Expected: PASS, with the boundary test green. "senate" and "house" appear only under `adapters/federal/`.

- [ ] **Step 5: Commit**

`git commit -m "feat: search people by name and by place"`

---

### Task 6: A page for every person

**Files:**
- Create: `lib/everyday_citizen_web/live/rep_panel.ex`. The rep panel moves here from `RepsLive`: assigns, summary loading, feed paging, events, and the `rep_panel/1` component with `activity_item`.
- Modify: `lib/everyday_citizen_web/live/reps_live.ex` (use `RepPanel`; the rep's name links to `/people/:id`; the district shows `Reps.district_label/1`)
- Create: `lib/everyday_citizen_web/live/person_live.ex`
- Modify: `lib/everyday_citizen_web/router.ex` (`live "/people/:id", PersonLive` in the `:current_user` live_session)
- Modify: `lib/everyday_citizen/legislature.ex` (`get_person/1`, `latest_chamber_membership/1`, `committee_roles/2`)
- Modify: `lib/everyday_citizen/legislation.ex` (`sponsored_bills/3`)
- Test: `test/everyday_citizen_web/live/person_live_test.exs`, `test/everyday_citizen_web/live/reps_live_test.exs` (still green, plus a link assertion)

**Interfaces:**
- Produces:
  - `RepPanel.assign_rep(socket, rep :: Reps.rep() | nil, params :: map(), path :: (filter :: String.t() | nil, week :: Date.t() | nil -> String.t())) :: socket`. It sets `rep`, `filter`, `week`, `this_monday`, `counts`, `following`, the feed, and the week summary, which keeps the crawler, rate-limit and budget rules exactly as today.
  - `RepPanel.handle_info/2` for `{:ai_summary, "rep_week", subject, result}`.
  - `RepPanel.handle_event/3` for `"toggle_follow"` and `"more"`.
  - Function component `<RepPanel.rep_panel …/>`, taking the same assigns `RepsLive` renders today.
  - Both LiveViews delegate to these, so nothing is duplicated.
- Produces: `Legislature.get_person(id :: String.t() | integer()) :: Person.t() | nil`. Non-integer ids return nil.
- Produces: `Legislature.latest_chamber_membership(person_id) :: %{membership: Membership.t(), body: Body.t()} | nil`, covering ended memberships too.
- Produces: `Legislature.committee_roles(person_id, on :: Date.t()) :: [%{body: Body.t(), role: String.t()}]`. These are current memberships of bodies with classification `committee` or `subcommittee`. Committees come first, subcommittees under them, then by name.
- Produces: `Legislation.sponsored_bills(person_id, classification :: "primary" | "cosponsor", opts :: [limit: 10, offset: 0]) :: %{bills: [%{bill: Bill.t(), latest: BillAction.t() | nil}], total: non_neg_integer()}`, newest introduced first.

Person page layout, phone first, following the mockup's screen 3:
1. **Header:** photo if `image_url`, otherwise initials. Then the name, and `body.name · party · district_label`, with "since <Mon YYYY>" from the earliest `start_date` in that body. For a former member, "Served until <Mon YYYY>".
2. **Follow**, using the existing `follow_button`.
3. **The rep panel:** week summary, week switcher, filters and activity. It opens on the latest active week, as the reps page does.
4. **Bills they sponsored**, and **bills they cosponsored** with the total. Show 5 of each, then a "Show more" button that loads 10 more in place (events `"more_sponsored"` and `"more_cosponsored"`).
5. **Committees:** name and role.

`page_title` is the person's name. An unknown id returns 404 (`EverydayCitizenWeb.NotFoundError`, as `BillLive` does).

Ruling for the ledger: the spec's "Recent votes, then All votes" is the panel's Votes filter. It is not a second list, because the spec says to reuse the panel. Cost if wrong: one more section.

- [ ] **Step 1: Write the failing tests**

```elixir
test "a person's page shows who they are, their week, their bills and committees" do
  %{grassley: p} = fixtures()
  {:ok, view, html} = live(conn, ~p"/people/#{p.id}")
  assert html =~ "Chuck Grassley"
  assert html =~ "Senate · Republican · Iowa"
  assert has_element?(view, "#follow-rep")
  assert has_element?(view, "#week")
  assert html =~ "Bills they sponsored"
  assert html =~ "S. 5"
  assert html =~ "Judiciary"
end

test "a former member's page shows their last role and record" do
  {:ok, _view, html} = live(conn, ~p"/people/#{former.id}")
  assert html =~ "Served until Jan 2023"
end

test "show more loads further cosponsored bills in place" do
  # 7 cosponsorships
  {:ok, view, _} = live(conn, ~p"/people/#{p.id}")
  assert view |> element("button[phx-click=more_cosponsored]") |> render_click() =~ "7th bill title"
end

test "an unknown person is not found" do
  assert_raise EverydayCitizenWeb.NotFoundError, fn -> live(conn, ~p"/people/999999") end
  assert_raise EverydayCitizenWeb.NotFoundError, fn -> live(conn, ~p"/people/abc") end
end

test "a crawler never starts a week summary on a person page" do
  # same shape as the existing reps_live crawler test, against /people/:id
end

# reps_live_test.exs
test "the selected rep's name links to their page" do
  {:ok, view, _} = live(conn, ~p"/reps/IA-1")
  assert has_element?(view, ~s(a[href="/people/#{rep.id}"]))
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen_web/live/person_live_test.exs`
Expected: FAIL, with no route.

- [ ] **Step 3: Extract `RepPanel` from `RepsLive` with no change in behaviour**

Run: `mix test test/everyday_citizen_web/live/reps_live_test.exs`
Expected: PASS, before any new feature is added.

- [ ] **Step 4: Implement the context functions, `PersonLive`, the route and the reps-page link**

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 6: Phone-width screenshot check**

Start the local server and screenshot `/people/<id>` at 400px with headless Chrome, using a temporary `priv/static/images/zz-frame.html`. Delete it afterwards.
Expected: no horizontal scroll, and the header wraps cleanly.

- [ ] **Step 7: Commit**

`git commit -m "feat: a page for every person"`

---

### Task 7: The search box and results page

**Files:**
- Modify: `lib/everyday_citizen_web/components/layouts.ex` (search form in the header, a full-width row under the brand on phones and inline on large screens)
- Modify: `lib/everyday_citizen_web/components/layouts/root.html.heex` (`<meta :if={assigns[:noindex]} name="robots" content="noindex" />`)
- Create: `lib/everyday_citizen_web/controllers/search_controller.ex`
- Create: `lib/everyday_citizen_web/live/search_live.ex`
- Modify: `lib/everyday_citizen_web/router.ex` (`post "/search", SearchController, :create` in the browser scope; `live "/search", SearchLive` in `:current_user`)
- Modify: `config/config.exs` (add `"q"` to `:filter_parameters`)
- Test: `test/everyday_citizen_web/controllers/search_controller_test.exs`, `test/everyday_citizen_web/live/search_live_test.exs`

**Interfaces:**
- Consumes: `Query.classify/1` (Task 3), `Search.bill_by_number/1`, `bills_by_name/2`, `bills_by_text/3` (Task 4), `Search.people/2` (Task 5), and the `/people/:id` route (Task 6).
- Produces: the form posts `q` to `/search` (`<.form for={to_form(%{"q" => ""})} action={~p"/search"} method="post">`, with CSRF included). Use `id="site-search"` and the input `id="site-search-q"`, placeholder "Search bills and people", with `aria-label` the same.

Ruling for the ledger: the spec's "Details settled" says a LiveView event through an `on_mount` hook. A plain POST to a controller does the same job more simply: it works on every page, LiveView or not, and puts nothing in a URL until the controller decides. Cost if wrong: swap the form's target.

**Controller `create/2`:**
- `:empty` → redirect back to the referring page, or `/`. No flash.
- `:address` → redirect to `/` with flash info: "That looks like an address. Enter it here to find your representatives." The query is not carried along.
- `{:search, q}` with `bill_by_number(q) == {:one, bill}` → redirect to `/bills/#{bill.external_id}`.
- Otherwise → redirect to `~p"/search?#{[q: q.text]}"`.

**`SearchLive`:**
- It sets `noindex: true` and `page_title: "Search"`.
- It reads `q` from params and classifies it again. A hand-typed `:address` shows the same message as a link to `/`, runs no search and builds no links containing it. `:empty` shows a short prompt.
- Otherwise it renders the groups, in the mockup's order:
  1. **Bill numbers:** `{:many, …}` from `bill_by_number`, labelled "Bills numbered <n>".
  2. **"Bills with this name":** up to 10 from `bills_by_name`.
  3. **"Bills whose text mentions it":** 10 per page, with `?q=…&page=N` links for further pages. The heading count is "N more bills mention it" when `more?`.
  4. **People:** the place group first, titled with the place name, with each member showing `body.name · party · district_label`. Then people by name.
- An empty group is left out.
- With no results at all: "Nothing matched “<q>”. Check the spelling, or search for a bill number or a person's name."
- When `websearch_to_tsquery` produced nothing and the other groups are empty: "Try more specific words."
- Each bill result shows: the identifier, the matched title (a link), a status line from `stage`, and the cached AI summary when present, under the label "Written by AI from the bill; it can be wrong".
- Each text result shows: `Sec. …`, then the excerpt with `:mark` parts as `<mark>` (escaped text otherwise).

- [ ] **Step 1: Write the failing tests**

```elixir
# search_controller_test.exs
test "an address is never searched or put in a URL" do
  conn = post(conn, ~p"/search", %{"q" => "123 Main St"})
  assert redirected_to(conn) == "/"
  refute redirected_to(conn) =~ "Main"
  assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "looks like an address"
end

test "a bill number goes straight to the bill" do
  assert redirected_to(post(conn, ~p"/search", %{"q" => "s5"})) == "/bills/119-s-5"
end

test "an ordinary query opens the results page" do
  assert redirected_to(post(conn, ~p"/search", %{"q" => "laken riley"})) == "/search?q=laken+riley"
end

test "q is filtered from logs" do
  assert "q" in Application.fetch_env!(:phoenix, :filter_parameters)
end

# search_live_test.exs
test "results show name matches, text matches and people, and the page is noindex" do
  {:ok, view, html} = live(conn, ~p"/search?q=laken riley")
  assert html =~ ~s(name="robots" content="noindex")
  assert has_element?(view, "section[aria-label='Bills with this name'] a[href='/bills/119-s-5']")
end

test "a hand-typed address in the URL is not searched" do
  {:ok, _view, html} = live(conn, ~p"/search?q=123 Main St")
  assert html =~ "looks like an address"
  refute html =~ "Main St\""
  refute html =~ "Bills with this name"
end

test "a state search lists its members with links to their pages" do
  {:ok, view, _} = live(conn, ~p"/search?q=iowa")
  assert has_element?(view, ~s(a[href="/people/#{grassley.id}"]))
end

test "no AI summary is started by searching" do
  live(conn, ~p"/search?q=laken riley")
  refute_enqueued worker: EverydayCitizen.Jobs.SummarizeSubject
end

test "nothing matched" do
  {:ok, _view, html} = live(conn, ~p"/search?q=zzzzqqq")
  assert html =~ "Nothing matched"
end

test "the search box is on every page" do
  {:ok, view, _} = live(conn, ~p"/this-week")
  assert has_element?(view, "form#site-search[action='/search'][method='post'] input[name=q]")
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen_web/controllers/search_controller_test.exs test/everyday_citizen_web/live/search_live_test.exs`
Expected: FAIL, with no route.

- [ ] **Step 3: Implement the controller, the LiveView, the layout form, the noindex meta, the routes and the filter param**

- [ ] **Step 4: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Phone-width screenshot check of `/search?q=iowa` and of the header on `/`**

Expected: no horizontal scroll; the search box takes the full width under the brand on phones.

- [ ] **Step 6: Commit**

`git commit -m "feat: search box on every page and a results page"`

---

### Task 8: Every name on a bill page links to that person

**Files:**
- Modify: `lib/everyday_citizen/bill_page.ex` (`cosponsors` list in the page map; `vote_positions/1`)
- Modify: `lib/everyday_citizen_web/live/bill_live.ex`
- Modify: `lib/everyday_citizen_web/components/bill_history_components.ex`
- Test: `test/everyday_citizen_web/live/bill_live_test.exs`, `test/everyday_citizen_web/live/bill_history_live_test.exs`

**Interfaces:**
- Produces: `BillPage.load/3` (existing) also returns `cosponsors: [Person.t()]`, ordered by sponsorship date then name, with withdrawn cosponsors left out.
- Produces: `BillPage.vote_positions(vote_id :: integer()) :: [{option :: String.t(), [Person.t()]}]`, grouped in the order yea, nay, present, not voting (as `vote_chip` names them), and by name within each group.

Changes on the bill page:
- The sponsor's name is a link.
- "N cosponsors" opens a `<details>` listing every cosponsor as a link.
- "Your reps on this bill": each name is a link.
- Each vote card gets a "Who voted how" `<details>` with `phx-click="positions"` and `phx-value-vote={vote.id}` on its `<summary>`. On the first open it loads `vote_positions/1` into an assign `positions` (a map of vote id to groups) and renders the names as links. Positions are loaded lazily, because a chamber roll call has hundreds of names.
- In `bill_history_components.ex`, `rep.person.name` becomes a link.
- Link targets are always `~p"/people/#{person.id}"`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "the sponsor and cosponsors link to their pages" do
  {:ok, view, _} = live(conn, ~p"/bills/119-s-5")
  assert has_element?(view, ~s(a[href="/people/#{grassley.id}"]), "Chuck Grassley")
  assert has_element?(view, ~s(details a[href="/people/#{ernst.id}"]))
end

test "who voted how loads on opening and links every name" do
  {:ok, view, _} = live(conn, ~p"/bills/119-s-5")
  html = view |> element("summary[phx-click=positions]") |> render_click()
  assert html =~ ~s(href="/people/#{ernst.id}")
end

test "reps named in the text history link to their pages" do
  # in bill_history_live_test.exs, using the existing fixture with an amendment sponsor
  assert has_element?(view, ~s(a[href="/people/#{rep.id}"]))
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `mix test test/everyday_citizen_web/live/bill_live_test.exs test/everyday_citizen_web/live/bill_history_live_test.exs`
Expected: FAIL, with no such links.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -m "feat: every name on a bill page links to that person"`

---

### Task 9: Record, review and ship

**Files:**
- Modify: `docs/DECISIONS.md`. Append, never rewrite, one line each for:
  - the `bill_titles` table and title kinds, including `part`;
  - `ec_name_key` as the single name-comparison rule;
  - the full-text expression index on the latest version, chosen at query time;
  - the place and district-label callbacks on `Reps.Locator`;
  - POST search with address classification;
  - `/people/:id` on internal ids;
  - search pages `noindex`.
- Modify: `CLAUDE.md` "Current milestone" with one line naming this plan.

- [ ] **Step 1: Write the decision lines and the CLAUDE.md line**

- [ ] **Step 2: Run `mix precommit` and `mix credo --strict`**

Expected: both clean.

- [ ] **Step 3: Final whole-branch review** (per the execution skill)

- [ ] **Step 4: Check production disk headroom before migrating**

Run: `fly ssh console -a thefloor-vote-db -C "df -h /data"`
Expected: at least 1.5 GB free. Stop and ask the owner if less.

- [ ] **Step 5: Merge `--no-ff` to main, push, and wait for the CI run for that exact SHA**

Run: `gh run list --commit <sha>`
Expected: success, and the blue/green deploy completes.

- [ ] **Step 6: Check `pg_trgm` and the indexes in production, then enqueue the backfill**

Run in order:
1. `EverydayCitizen.Repo.query!("select extname from pg_extension")`. Expected: `pg_trgm` is listed.
2. The index size query from Task 4. Expected: under 100 MB.
3. `EverydayCitizen.Release.ingest("bill_titles")`. Expected: `enqueued` of about 19,800.

- [ ] **Step 7: Check production**

Run: `curl --resolve everydaycitizen.vote:443:66.241.124.174`. Check:
- `/search?q=laken+riley` lists S. 5;
- `/search?q=ohio` lists Ohio's members;
- a `/people/<id>` page renders;
- `POST /search` with "hr22" redirects to H.R. 22.

After the backfill has run for an hour, check that `/search?q=big+beautiful+bill` lists H.R. 1 first.
