# Section origins worked out at ingest — Plan

**Goal:** a bill page reads each section's origin ("Since introduced", "Changed", "Added") from the database instead of working it out on every visit. It is worked out once, when a bill's versions change.

**Why (owner, 2026-10-26):** working out origins reads every version's text and normalizes every paragraph. On long bills this took 20 s to 5 min a page and saturated the CPU. It now runs only on the live page (merge after 7f3fbf1), but every live visit still repeats it. The result depends only on the bill's versions, and those change only at ingest.

## Global Constraints

- No visible change on the page: the same tags, the same "added in" lines and the same history panel. The existing tests (`bill_history_test.exs`, `bill_history_live_test.exs`, `bill_live_test.exs`) pass unchanged, except tests that set up versions directly, which also run the job (Task 2).
- No federal words in `lib/**/*.ex` outside the adapter. The job is shared code. Adapters keep only fetch, normalize and write.
- The migration only adds a nullable column (deploy rule). Check database disk headroom before the backfill.
- `mix precommit` and `mix credo --strict` clean before each commit.

## Design

- **Storage.** `bill_versions.origins` (jsonb, nullable) holds a map from section index to `%{status, added_in, changed_in}`, the shape `BillHistory.origins/3` returns today. `nil` means not yet worked out; `%{}` means nothing to compare (fewer than two versions with sections).
- **Working it out.** `EverydayCitizen.Jobs.ComputeOrigins` takes `%{"bill_id" => id}`. It loads the bill's versions once (`BillHistory.load/1`), computes `origins/3` for each version with sections, and writes them all in one transaction. It is unique per bill for a few minutes, so a burst of writes to one bill queues it once. It runs in the `text` queue at a low priority.
- **When it runs.** The writer enqueues it after any write that can change a bill's origins: a version's date or code (`Records.BillVersion`), its text or sections (`Records.BillVersionText`), and `Legislation.put_sections/3` (the section backfill). An origin depends on every earlier version, so the whole bill is recomputed.
- **Reading.** `BillLive` takes `origins` from the shown version's stored column (`BillPage.sections/2` already loads that row). It no longer calls `BillHistory.origins/3`. If the column is `nil`, it shows no tags. Opening a changed section still loads the bill's versions for its comparison and steps. Only a person can do that, one section at a time, so it is left as it is.
- **The first fill.** A one-off `mix`/release task enqueues the job for every bill with two or more versions with sections (about 1,800 locally). Bills with one version get `%{}` directly in SQL.

## Tasks

### Task 1: Column and job
- Migration: add `bill_versions.origins :map`, nullable.
- Tests first (`test/everyday_citizen/jobs/compute_origins_test.exs`):
  - after the job, each version's stored origins equal `BillHistory.origins(bill, code)`;
  - a bill with one version stores `%{}`;
  - running it twice changes nothing.
- Implement `ComputeOrigins` and `Legislation.put_origins/2`. Integer keys come back from jsonb as strings, so reading converts them.
- Commit.

### Task 2: Enqueue on write
- Tests first: writing a `Records.BillVersion`, a `Records.BillVersionText`, or calling `put_sections/3` enqueues one job for that bill (`assert_enqueued`), and the job is unique per bill.
- Implement in the writer and in `put_sections/3`.
- Commit.

### Task 3: The page reads stored origins
- Tests first: a bill page whose versions have stored origins shows the tags without the page loading every version's sections. Use the telemetry watcher pattern from `home_live_test.exs`: no query selects `sections` from more than one version. A version with `origins: nil` shows no tags.
- Existing history tests set up versions with `Ingest.write`. They run the queued job with `Oban.drain_queue(queue: :text)` (or `perform_job`) in their setup.
- Implement in `BillLive`: remove `assign_origins`'s computation and keep the opened-section path.
- Commit.

### Task 4: Fill existing bills
- A release task, `EverydayCitizen.Release.compute_origins/0`:
  - sets `%{}` on versions of single-version bills;
  - enqueues the job for the rest;
  - reports the counts.
- Test it on fixtures.
- After deploy, check disk headroom and run it. The owner runs it with `!` if an rpc write is blocked.
- Commit; DECISIONS entry.

## Review Focus

1. A new version arriving (or a version's date changing order) recomputes every version of that bill, not only the new one.
2. A page between the deploy and the backfill (origins `nil`) renders without tags and without errors.
3. The section backfill job (`BackfillBillSections`) over thousands of versions queues one job per bill, not one per version.
4. jsonb round-trip: atom statuses and integer keys come back as the page expects.
