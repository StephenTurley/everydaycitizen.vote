# Bulk Bill Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first bill ingest (empty database) loads every bill and its text from GovInfo bulk zips in tens of minutes instead of ~25 hours of Congress.gov requests; nightly incremental runs stay on the API.

**Architecture:** `SyncBills` with no cursor (first run) takes a bulk path: download `BILLSTATUS-{congress}-{type}.zip` for each of the 8 bill types, convert each BILLSTATUS XML file into the same maps the Congress.gov API returns, and write them through the existing `Normalize.Bill` functions and writers, so both paths produce identical records. The run is recorded as `sync_bills`, so the next nightly run's cursor is the backfill's start (minus the existing 2-day overlap, which also covers the hours the bulk files lag the API). A follow-up `BackfillBillText` job loads version text from `BILLS-{congress}-{session}-{type}.zip` the same way. Anything the zips miss falls back to the existing per-bill and per-version jobs.

**Tech Stack:** Elixir, Oban, Req (existing `Federal.HTTP`), Saxy (simple form), Erlang `:zip`.

**Spec:** `docs/SPEC.md` (§5 sources, §7.1 ingest, §8 M1 done-when).

## Global Constraints

- Federal code only under `lib/the_floor/adapters/federal/`; the boundary test must keep passing.
- Every record carries provenance. For a bulk record: `url` = the per-file bulkdata URL of that entry (e.g. `https://www.govinfo.gov/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119hr152.xml`), `fetched_at` = when the zip was downloaded, `content_hash` = SHA-256 of the entry's bytes (the same bytes the per-file URL serves).
- Prefer official primary sources: GovInfo bulk data is the official source the Congress.gov API is built from.
- Downloads use the `:govinfo` rate limiter. Zips go to a temp file deleted after use; entries are read one at a time, so memory holds one zip (≤ ~45 MB) plus one entry, never the whole extract (the Fly machine has 512 MB).
- `mix precommit` and `mix credo --strict` clean before each commit; decisions appended to `docs/DECISIONS.md`.

## Review Focus

1. A bulk file that differs from the API shape in a field we read (e.g. `textVersions` formats have only `url`, no `type`). Expect: records identical to the API path. Pinned by the parity test in Task 2.
2. A bill present in the Congress.gov listing but missing from the zip (bulk lags by hours). Expect: picked up by the next nightly incremental run via the 2-day overlap, and coverage tolerates the lag. Pinned in Task 3.
3. A malformed or unparseable entry. Expect: logged, that bill falls back to a `SyncBill` API job, and the backfill continues. Pinned in Task 3.
4. A bulk text file for a version not stored, or a stored version missing from the zips. Expect: the first is ignored, the second falls back to `SyncBillText`. Pinned in Task 4.
5. Members still being written when bills start. Expect: bills wait for a succeeded `sync_members` run (this closes parked residual 1). Pinned in Task 3.

---

### Task 1: Bulk zip download and entry iteration

**Files:**
- Create: `lib/the_floor/adapters/federal/bulk.ex`
- Test: `test/the_floor/adapters/federal/bulk_test.exs`

**Interfaces:**
- Produces: `Bulk.with_zip(url, fun) :: {:ok, term()} | {:error, term()}`, which downloads `url` through `HTTP.get(url, limiter: :govinfo, decode: :raw)`, writes it to a temp file, calls `fun.(zip)`, and always deletes the file. Also `Bulk.reduce_entries(zip, acc, fun) :: acc`, which calls `fun.({name, bytes, %SourceRef{}}, acc)` per `.xml` entry, one entry in memory at a time (`:zip.zip_open` / `zip_get`). The SourceRef's url is `entry_base_url <> name`, where `entry_base_url` is the zip URL's directory; `fetched_at` is the download time and the hash is over `bytes`.
- Rejects a 200 HTML page (`HTTP.html?/1`) as `{:error, :not_a_zip}`.

- [ ] Test `reduce_entries visits each xml entry with a per-file source`: build a zip in the test with `:zip.create(~c"t.zip", [{~c"A.xml", "<a/>"}, {~c"B.xml", "<b/>"}, {~c"readme.txt", "x"}], [:memory])`, stub it with `Req.Test`. Assert two entries, names `A.xml` and `B.xml`, source urls `…/dir/A.xml`, and hash = `SourceRef.new(url, "<a/>").content_hash`.
- [ ] Test `with_zip deletes the temp file even when fun raises`.
- [ ] Test `with_zip returns {:error, :not_a_zip} for an HTML 200`.
- [ ] Implement, run, commit `feat(federal): GovInfo bulk zip download and iteration`.

### Task 2: BILLSTATUS XML → API-shaped maps

**Files:**
- Create: `lib/the_floor/adapters/federal/normalize/bill_status.ex`
- Create fixture: `test/support/fixtures/federal/govinfo/BILLSTATUS-119hr22.xml` (real file from `https://www.govinfo.gov/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119hr22.xml`, saved as fetched)
- Test: `test/the_floor/adapters/federal/normalize/bill_status_test.exs`

**Interfaces:**
- Produces: `BillStatus.parse(xml) :: {:ok, %{detail: map(), subjects: map(), actions: [map()], cosponsors: [map()], text: map()}} | {:error, term()}`, shaped exactly like the Congress.gov responses `SyncBill` passes to `Normalize.Bill`: `detail = %{"bill" => bill}`, `subjects = %{"subjects" => %{"legislativeSubjects" => [...]}}`, `text = %{"textVersions" => [...]}`.
- Conversion: a generic Saxy simple-form walk, where an element whose children are all `<item>` becomes a list, a leaf becomes its text, and anything else becomes a map. Then fix-ups for known differences: each `textVersions[].formats[]` entry gets `"type"` inferred from its URL (`.xml` → `"Formatted XML"`, `.htm` → `"Formatted Text"`, `.pdf` → `"PDF"`).

- [ ] Parity test `bulk and API produce the same records for 119 hr 22`: feed both the existing API fixtures (`congress_gov/bill_119_hr_22/*`) and the BILLSTATUS fixture through `Normalize.Bill.bill/3`, `actions/3`, `sponsorships/4` and `versions/3`. Assert equal after dropping `source`. Any field difference found while making this pass gets a fix-up plus a one-line comment naming the difference.
- [ ] Test `malformed XML returns {:error, _}` (use `govinfo/malformed.xml`).
- [ ] Implement, run, commit `feat(federal): BILLSTATUS bulk XML in API shape`.

### Task 3: Bulk path for the first SyncBills run

**Files:**
- Create: `lib/the_floor/adapters/federal/bill_writer.ex` (the write half of `SyncBill`: `write(parts, sources, run_id) :: {:ok, [version_code]} | {:error, term()}`)
- Modify: `lib/the_floor/adapters/federal/jobs/sync_bill.ex` (fetch, then `BillWriter.write`)
- Modify: `lib/the_floor/adapters/federal/jobs/sync_bills.ex` (nil cursor → bulk path)
- Modify: `lib/the_floor/adapters/federal/prerequisites.ex` (add `members_synced/0`)
- Test: `test/the_floor/adapters/federal/jobs/sync_bills_bulk_test.exs`; existing `sync_bill` tests must pass unchanged.

**Interfaces:**
- Consumes: `Bulk.with_zip/2`, `Bulk.reduce_entries/3`, `BillStatus.parse/1`.
- Produces: `SyncBills` on its first run (no succeeded `sync_bills` run) iterates `BILLSTATUS-{c}-{t}.zip` for `t in ~w(hr s hjres sjres hconres sconres hres sres)` inside `Job.run("sync_bills", …)`. Stats: `%{source: "bulk", written: n, fallback: m}`. With a cursor it is unchanged.
- Each entry goes through `BillStatus.parse` and `BillWriter.write` with that entry's SourceRef for every record. On a parse or write error it logs and enqueues `SyncBill` for that bill, taking the bill id from the entry name (`BILLSTATUS-119hr152.xml`). A failed zip download fails the run, so the cursor stays nil and the next run retries the bulk path.
- The bulk path does not enqueue `SyncBillText` per version. It enqueues one `BackfillBillText` (Task 4) at the end.
- Prerequisite: bills now also wait for `Provenance.last_succeeded_run("federal", "sync_members")` (`Prerequisites.members_synced/0`), using the same snooze cap.

- [ ] Test `first run loads bills from the bulk zip and records a sync_bills run`: a stubbed zip with the hr22 fixture and one malformed entry. Assert the bill, actions, sponsorships and versions are stored with bulkdata source urls; one `SyncBill` job is enqueued for the malformed entry; one `BackfillBillText` job is enqueued; the run succeeded with `source: "bulk"`.
- [ ] Test `a later run uses the API listing with the cursor` (no zip requests made).
- [ ] Test `bills snooze until a sync_members run has succeeded`.
- [ ] Implement, run, commit `feat(federal): first bill sync from BILLSTATUS bulk data`.

### Task 4: BackfillBillText from BILLS zips

**Files:**
- Create: `lib/the_floor/adapters/federal/jobs/backfill_bill_text.ex` (queue `:text`)
- Modify: `lib/the_floor/adapters/federal/jobs/sync_bill_text.ex` (extract `store/5` as a public function so both use it)
- Test: `test/the_floor/adapters/federal/jobs/backfill_bill_text_test.exs`

**Interfaces:**
- Consumes: `Bulk`, `XmlText.plain_text/1`, `Legislation.versions_missing_text/1`.
- Produces: for each stored child session × bill type, iterates `BILLS-{c}-{session}-{t}.zip`. For each entry `BILLS-119hr152ih.xml` → (`119-hr-152` external id, code `ih`) whose version has no text, it stores XML and plain text with the entry's SourceRef. Entries for unknown versions are skipped. Afterwards it enqueues `SyncBillText` for every version still missing text. Runs as `Job.run("backfill_bill_text", …)`; stats `%{stored: n, fallback: m}`.

- [ ] Test `stores text for versions in the zip and falls back for the rest`: two stored versions, a zip holding one of them (`BILLS-119hr22ih.xml` fixture) and one unknown entry. Assert one text stored with a bulkdata url, one `SyncBillText` enqueued, and the unknown entry ignored.
- [ ] Test `HTML or unparseable entries are skipped and fall back`.
- [ ] Implement, run, commit `feat(federal): bill text backfill from BILLS bulk data`.

### Task 5: Docs and live check

**Files:** `README.md`, `docs/DECISIONS.md`, `lib/the_floor/adapters/federal/jobs.ex` (registry: add `backfill_bill_text` so it can be run by name)

- [ ] Live check, local dev DB: download the real `BILLSTATUS-119-sconres.zip` (smallest) and run the bulk path for that type only from IEx. Compare the stored count with the Congress.gov count for sconres. Separately, confirm one entry's hash equals the SHA-256 of the per-file URL's body (this backs the provenance claim).
- [ ] README: replace the 25-hour estimate with the bulk first run and its measured time. Note that bulk files lag the API by hours and the next nightly run catches up.
- [ ] DECISIONS entry: first bill and text ingest from GovInfo bulk, provenance per entry, cursor from the bulk run, members prerequisite.
- [ ] Commit `docs: bulk backfill`.
