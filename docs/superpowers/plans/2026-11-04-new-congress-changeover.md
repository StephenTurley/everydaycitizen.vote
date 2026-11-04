# New Congress Changeover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** on Jan 3, 2027 (and on Jan 3 of every odd year after it), the site switches to the new Congress by itself: new bills, votes and schedules come in, reps change, and nobody is shown a rep from a district map that no longer applies.

**Architecture:** the adapter works out the sitting Congress from the date (`Federal.Congresses`) instead of reading `congress: 119` from config. Each place that maps addresses to districts (the Census lookup, the ZIP table, a saved district in a session or account) records which district map it came from. The locator reports the current map, and anything from an older map is set aside: ZIP lookup asks for the street address, and a saved district is dropped with a notice to look the address up again. Bill sync keeps listing the previous Congress for 30 days, so bills signed or vetoed in January still get their last steps.

**Tech Stack:** Elixir 1.20, Phoenix 1.8 LiveView, Ecto/Postgres, Oban, Req (with `Req.Test` stubs).

**Spec:** the design was approved in chat on 2026-11-04 and is recorded here:
1. The Congress number comes from the date. It changes on Jan 3 of every odd year (the 120th starts in 2027). Every job that used the config switches with it.
2. The previous Congress keeps syncing bills for 30 days after the switch.
3. Each Congress has its own Census map (`census_vintages`, with 120 added). The ZIP table records its map. When that map is older than the current one, ZIP lookup is skipped and the visitor is asked for the street address, until the new ZIP file is loaded.
4. A saved district (session and account) records its map. One from an older map is dropped, and a notice asks the person to look up their address again.
5. Reps change on the date, as they already do. Fix the one day when both the outgoing and the incoming member show.
Out of scope: projected winners (members-elect) and emails to followers of departing members.

## Global Constraints

- No federal words in `lib/**/*.ex` outside `lib/everyday_citizen/adapters/federal/` (`boundary_test.exs`). Domain and web code say "district map", never "congress".
- UI copy never names a legislature. The notice text is exactly: "District lines have changed since you last looked up your address. Enter it again to see your representatives."
- Street addresses and ZIP codes are never stored, logged, put in URLs or sent to Sentry.
- Tests never call third-party APIs; HTTP goes through `Req.Test` stubs as the existing job tests do.
- Migrations only add nullable columns and work with the old code (`docs/ops/deploys.md`).
- `mix precommit` clean and `mix credo --strict` exit code 0 before each commit.
- Append to `docs/DECISIONS.md`; never rewrite it.

## Review Focus

1. A session cookie from before this deploy has a district but no map. It gets stamped with the current map, and the visitor sees no notice (Task 4 test).
2. After the migration, before the ZIP file is reloaded, ZIP rows have no map. A ZIP lookup asks for the full address and doesn't crash (Task 3 test).
3. A visitor follows an old `/district/OH-3` link after the switch. The district is saved with the current map and no notice is shown, because they chose it just now (Task 4 test).
4. On Jan 3, Congress.gov may not list the 120th yet. `SyncCongress` waits (snoozes) instead of failing three times into Sentry, and the jobs that need the session keep waiting as they do now (Task 1 test).
5. The 121st Congress: the Census layer is named "121st Congressional Districts", not "121th" (Task 3 test).

---

### Task 1: The sitting Congress comes from the date

**Files:**
- Create: `lib/everyday_citizen/adapters/federal/congresses.ex`
- Modify: every `Application.fetch_env!(:everyday_citizen, :federal)[:congress]` in `lib/everyday_citizen/adapters/federal/` (14 sites: `coverage.ex`, `geocoder.ex`, and the jobs `coverage`, `backfill_bill_text`, `sync_bills`, `sync_senate_floor`, `backfill_bill_summaries`, `sync_house_floor`, `link_vote_subjects`, `sync_congress`, `sync_committee_meetings`, `sync_house_votes`, `sync_members`, `sync_senate_votes`)
- Modify: `lib/everyday_citizen/adapters/federal/jobs/sync_congress.ex` (snooze on 404)
- Modify: `config/config.exs` (drop `congress: 119`), `config/test.exs` (add `today: ~D[2026-11-04]` under `:federal`)
- Test: `test/everyday_citizen/adapters/federal/congresses_test.exs`, `test/everyday_citizen/adapters/federal/jobs/sync_congress_test.exs`

**Interfaces:**
- Produces:
  - `Congresses.current() :: pos_integer()`, which is `current(today())`.
  - `Congresses.current(Date.t()) :: pos_integer()`.
  - `Congresses.start_date(pos_integer()) :: Date.t()`, Jan 3 of the first year (valid from the 74th).
  - `Congresses.syncing() :: [pos_integer()]` and `syncing(Date.t())`: the current Congress, then the previous one while the date is before `start_date(current) + 30` days.
  - `Congresses.today() :: Date.t()`: `config :everyday_citizen, :federal, today:` when set (tests only), else today in `America/New_York` (`EverydayCitizen.Clock.today/1`).

- [ ] **Step 1: Write the failing tests** (`congresses_test.exs`)

```elixir
test "the sitting congress changes on Jan 3 of odd years" do
  assert Congresses.current(~D[2026-11-04]) == 119
  assert Congresses.current(~D[2027-01-02]) == 119
  assert Congresses.current(~D[2027-01-03]) == 120
  assert Congresses.current(~D[2025-01-02]) == 118
  assert Congresses.current(~D[2029-01-03]) == 121
end

test "start_date" do
  assert Congresses.start_date(120) == ~D[2027-01-03]
end

test "the previous congress syncs for 30 days" do
  assert Congresses.syncing(~D[2026-11-04]) == [119]
  assert Congresses.syncing(~D[2027-01-03]) == [120, 119]
  assert Congresses.syncing(~D[2027-02-01]) == [120, 119]
  assert Congresses.syncing(~D[2027-02-02]) == [120]
end

test "tests pin today from config" do
  assert Congresses.today() == ~D[2026-11-04]
  assert Congresses.current() == 119
end
```

In `sync_congress_test.exs`: when the stub answers `/congress/120` with 404, `perform_job(SyncCongress, %{"congress" => 120})` returns `{:snooze, 21_600}` (6 hours).

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/everyday_citizen/adapters/federal/congresses_test.exs test/everyday_citizen/adapters/federal/jobs/sync_congress_test.exs`
Expected: FAIL. `Congresses` is undefined, and SyncCongress returns an error on the 404.

- [ ] **Step 3: Implement `Congresses`, then replace the 14 config reads with `Congresses.current()`**

`args["congress"] || Congresses.current()` keeps per-job overrides. SyncCongress turns a 404 from `CongressGov.get/1` into `{:snooze, 21_600}`. Check how `CongressGov` reports a 404 before matching on it.

- [ ] **Step 4: Run the whole suite**

Run: `mix test`
Expected: all pass. `grep -rn ":federal)\[:congress\]" lib` prints nothing.

- [ ] **Step 5: Commit** (`changeover: the sitting congress comes from the date`)

### Task 2: Bill sync keeps the previous Congress for 30 days

**Files:**
- Modify: `lib/everyday_citizen/adapters/federal/jobs/sync_bills.ex`
- Test: `test/everyday_citizen/adapters/federal/jobs/sync_bills_test.exs` (create it if the incremental path has no test file; `sync_bills_bulk_test.exs` covers the first run)

**Interfaces:**
- Consumes: `Congresses.syncing/0` (Task 1).

- [ ] **Step 1: Write the failing tests.** Set up a succeeded `sync_bills` run so the incremental path runs. Then, with `Application.put_env` setting `today: ~D[2027-01-10]` (an `async: false` test that restores the env afterwards):
  - `test "lists the previous congress's bills too in the first 30 days"`: the `Req.Test` stub records request paths. Both `/bill/120` and `/bill/119` are requested with the same `fromDateTime`, and a `SyncBill` job is enqueued for a bill from each.
  - `test "lists only the sitting congress after 30 days"`: with `today: ~D[2027-02-02]`, only `/bill/120` is requested.
  - `test "an explicit congress argument lists only that congress"`: with `%{"congress" => 118}`, only `/bill/118` is requested.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/everyday_citizen/adapters/federal/jobs/sync_bills_test.exs`
Expected: FAIL. Only `/bill/120` is requested in the first test.

- [ ] **Step 3: Implement.** Without an args congress, the incremental `list` runs once per `Congresses.syncing()` entry inside the same `Job.run("sync_bills", …)`, so they share one cursor. Stats are keyed by congress: `%{"120" => %{enqueued: n}, "119" => …}`. The prerequisites check and the first-run bulk path use only the first (sitting) Congress.

- [ ] **Step 4: Run the job's tests, then `mix test`**
Expected: all pass.

- [ ] **Step 5: Commit** (`changeover: bill sync keeps the previous congress for 30 days`)

### Task 3: The district map in the locator, the Census lookup and the ZIP table

**Files:**
- Modify: `lib/everyday_citizen/reps/locator.ex` (new callback), `lib/everyday_citizen/reps.ex`
- Modify: `lib/everyday_citizen/adapters/federal/geocoder.ex`
- Modify: `lib/everyday_citizen/adapters/federal/jobs/sync_zip_districts.ex`, `lib/everyday_citizen/adapters/federal/normalize/zip_districts.ex`
- Modify: `lib/everyday_citizen/ingest/records.ex` (`PostalDistricts` gains `:district_map`), `lib/everyday_citizen/ingest/writer/postal_districts.ex`, `lib/everyday_citizen/legislature/postal_district.ex`, `lib/everyday_citizen/legislature.ex` (`postal_districts/3`)
- Create: migration `add_district_map_to_postal_districts` (`postal_districts.district_map :string`, nullable, no backfill)
- Modify: `config/config.exs`: `census_vintages: %{119 => "ACS2025_Current", 120 => "ACS2026_Current"}` and `zip_files: %{119 => "https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld/tab20_cd11920_zcta520_natl.txt"}` (the URL moves from the job's `@url`)
- Test: `geocoder_test.exs`, `sync_zip_districts_test.exs`, a `reps_test.exs` case

**Interfaces:**
- Consumes: `Congresses.current/0` (Task 1).
- Produces:
  - `@callback district_map() :: String.t()` on `Reps.Locator`. The federal geocoder returns `Integer.to_string(Congresses.current())`.
  - `Reps.district_map() :: String.t()`.
  - `Legislature.postal_districts(jurisdiction_key, postal_code, district_map) :: [String.t()]`, which matches only rows of that map.

- [ ] **Step 1: Write the failing tests**
  - Geocoder, `test "uses the next congress's map once it sits"`: with `today: ~D[2027-01-10]`, the stub asserts `vintage=ACS2026_Current` and answers with a `"120th Congressional Districts"` layer, and `locate/1` returns that district.
  - Geocoder, `test "the 121st congress's layer name"`: the private layer name comes from an ordinal helper. Assert through `locate/1` with `today: ~D[2029-01-10]`, a vintage configured for 121 in the test, and a stub answering `"121st Congressional Districts"`.
  - Geocoder, `test "a congress with no vintage is unavailable"`: with `today: ~D[2031-01-10]`, `locate/1` returns `{:error, :unavailable}` and makes no request.
  - Geocoder: `district_map/0` is `"119"` under the test config.
  - ZIP job, `test "records the map with the rows"`: stored rows have `district_map == "119"`.
  - ZIP job, `test "does nothing until the sitting congress's file is published"`: with `today: ~D[2027-01-10]`, the job succeeds with stats `%{skipped: :not_published}`, makes no request and leaves the table unchanged.
  - Reps, `test "ZIP lookup ignores rows from another map"`: rows with `district_map: "119"` and rows with `district_map: nil`. With the current map `"120"` (`today: ~D[2027-01-10]`), `Reps.districts_for_postal_code/1` returns `[]`. With `"119"`, it returns the 119 rows' districts.

- [ ] **Step 2: Run them and watch them fail**
Run: `mix test test/everyday_citizen/adapters/federal/geocoder_test.exs test/everyday_citizen/adapters/federal/jobs/sync_zip_districts_test.exs test/everyday_citizen/reps_test.exs`
Expected: FAIL. The callback, the column and the config keys don't exist yet.

- [ ] **Step 3: Implement.** The layer name uses an ordinal (`1st 2nd 3rd`, then `th`, with 11–13 taking `th`). `ZipDistricts.parse/3` takes the map. When a visitor's ZIP has no rows for the current map, the existing `:unknown_zip` message ("Enter your full address instead") already asks for the address, so no new copy is needed.

- [ ] **Step 4: `mix test`**, then `mix test test/everyday_citizen/boundary_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit** (`changeover: districts carry the map they came from`)

### Task 4: Saved districts carry their map; old ones are dropped with a notice

**Files:**
- Create: migration `add_district_map_to_users` (`users.district_map :string`, nullable)
- Modify: `lib/everyday_citizen/accounts/user.ex` (`district_changeset/3`), `lib/everyday_citizen/accounts.ex` (`put_district/3`)
- Modify: `lib/everyday_citizen_web/controllers/district_controller.ex` (`remember/2` saves the map)
- Modify: `lib/everyday_citizen_web/user_auth.ex` (`settle_district` and `restore_district` carry `:district_map` with `:district`)
- Create: `lib/everyday_citizen_web/saved_district.ex`, the plug `EverydayCitizenWeb.SavedDistrict`, added to the `:browser` pipeline right after `:fetch_current_scope_for_user`
- Test: `test/everyday_citizen_web/saved_district_test.exs`, plus cases in `user_auth_test.exs`

**Interfaces:**
- Consumes: `Reps.district_map/0` (Task 3).
- Produces:
  - Session keys `:district` and `:district_map`.
  - `Accounts.put_district(User.t(), String.t() | nil, String.t() | nil) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}`. It replaces `put_district/2`; update its callers.

The plug's rules, in order:
1. The session has no `:district`: do nothing.
2. `:district_map` is nil: put `Reps.district_map()` into the session, and on the account when its `district_map` is nil. This covers cookies and accounts from before this deploy.
3. `:district_map` differs from `Reps.district_map()`:
   - when signed in and the account's map is the current one, put the account's district and map into the session, with no notice, and stop here (the person looked it up again on another device);
   - otherwise delete both keys from the session;
   - when signed in and the account's map also differs, `put_district(user, nil, nil)`;
   - `put_flash(:info, "District lines have changed since you last looked up your address. Enter it again to see your representatives.")`.

- [ ] **Step 1: Write the failing tests** (`saved_district_test.exs`, through `get(conn, ~p"/")` with `init_test_session`)
  - `test "a district from an older map is dropped with the notice"`: with session `district: "OH-3", district_map: "118"` and the current map `"119"`, the response session has no `:district`, the page shows the notice and the address finder, and the page has no reps list.
  - `test "a signed-in person's old district is cleared from the account"`: the user has `district: "OH-3", district_map: "118"`. After the request, `Repo.reload(user).district == nil`.
  - `test "a district saved before maps were recorded is stamped, not dropped"`: with session `district: "OH-3"` and no map, the session afterwards has `district_map: "119"`, the reps show, and there is no notice.
  - `test "a current district is left alone"`.
  - `test "following a district link saves the current map"`: `get(conn, ~p"/district/OH-3")`, then the session has `district_map: "119"`, and the signed-in user's `district_map == "119"`.
  - `user_auth_test.exs`: signing in carries `:district_map` with `:district`, and the remember-me restore brings back both.

- [ ] **Step 2: Run them and watch them fail**
Run: `mix test test/everyday_citizen_web/saved_district_test.exs test/everyday_citizen_web/user_auth_test.exs`
Expected: FAIL. The plug doesn't exist and the map isn't saved.

- [ ] **Step 3: Implement** the migration, `put_district/3`, the controller, `user_auth.ex` and the plug.

- [ ] **Step 4: `mix test`**
Expected: all pass.

- [ ] **Step 5: Commit** (`changeover: saved districts from an older map are dropped with a notice`)

### Task 5: No double rep on the changeover day

**Files:**
- Modify: `lib/everyday_citizen/legislature.ex` (`current_members/3`, `current_members_matching/3`)
- Test: `test/everyday_citizen/legislature_test.exs`

- [ ] **Step 1: Write the failing tests**
  - `test "on the day a seat changes hands only the incoming member is current"`: House `OH-3`: A has `end_date: ~D[2027-01-03]`, B has `start_date: ~D[2027-01-03]`. `current_members("federal", [{"house", "OH-3"}], ~D[2027-01-03])` returns only B. On `~D[2027-01-02]` it returns only A.
  - `test "a senator continuing in office stays beside the incoming one"`: Senate `OH`: A ends Jan 3, B starts Jan 3, C runs to 2029. On Jan 3 the result is B and C.
  - `test "a member whose term ends with no successor yet is still listed on the last day"`: A ends `~D[2026-11-04]` and nobody starts that day. On that date the result is A.
  - The same three for `current_members_matching/3`.

- [ ] **Step 2: Run them and watch them fail**
Run: `mix test test/everyday_citizen/legislature_test.exs`
Expected: FAIL in the first two tests.

- [ ] **Step 3: Implement.** After the query, drop a row whose `end_date == on` when another row in the same body and district has `start_date == on`. Write it once, as a private function both queries use.

- [ ] **Step 4: `mix test`**
Expected: all pass.

- [ ] **Step 5: Commit** (`changeover: one member per seat on the day it changes hands`)

### Task 6: Records

**Files:**
- Modify: `docs/DECISIONS.md` (append one entry: Congress from the date, the 30-day bill window, district maps on the ZIP table and saved districts, the notice, the changeover-day rule)
- Create: `docs/ops/new-congress.md`, the checklist:
  - Before each Jan 3, check that `census_vintages` has the next Congress (the geocoder's `vintages` endpoint lists which layer each vintage carries).
  - When Census publishes the next ZIP relationship file (`tab20_cd1NN20_zcta520_natl.txt`), add it to `zip_files`, deploy, and run `zip_districts`.
  - After this deploy, run `zip_districts` once so the existing rows get their map.
  - On Jan 3, check `fly logs` for `sync_congress`, and check coverage the next morning.

- [ ] **Step 1: Write both, run `mix precommit`, and check that `mix credo --strict` exits 0**
- [ ] **Step 2: Commit** (`changeover: decision and runbook`)
