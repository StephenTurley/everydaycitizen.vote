# One AI-summary module, and search without reading bill text — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One module decides how a page gets an AI summary (cached, crawler, not yet live, visitor limit, queued) and tracks what the page listens for; search finds cached bill summaries without reading any bill's text.

**Architecture:** `EverydayCitizenWeb.AiBillSummary` becomes `EverydayCitizenWeb.AiSummary`, used by the bill page (bill summary, change explanation, section summaries), the reps panel (week summary) and the home page (new laws). Behaviour stays the same; the existing LiveView tests are the safety net and must pass unchanged.

**Why (backlog items 6 and 7, owner 2026-10-26):** the same decision is copied four times (`ai_bill_summary.ex:30-48`, `rep_panel.ex:131-162`, `bill_live.ex:225-250` and `:306-323`), each with its own unsubscribe and result matching, and `@repo_url`/`@hour` and the "Report a problem" map are repeated three times. A change to the crawler or limit rule has to be made four times. Search reads each named bill's full text to find its cached summary (`search.ex:337-344`), up to 20 heavy queries per search.

## Global Constraints

- No behaviour change visible to readers, crawlers or the budget, except the one fix named in Task 2.
- No federal words in `lib/**/*.ex` outside the adapter (`boundary_test.exs`).
- Tests never call outside services. `mix precommit` and `mix credo --strict` clean; commit only after both pass.

## Review Focus

1. A crawler never starts a summary on any of the four surfaces (existing crawler tests in bill, home, person and reps tests).
2. A page that changes version or section stops listening to the old topic, and a result for an old subject is ignored.
3. The visitor limit counts once per request, as now.

---

### Task 1: `AiSummary` with the shared decision

**Files:** rename `lib/everyday_citizen_web/ai_bill_summary.ex` to `ai_summary.ex`; test `test/everyday_citizen_web/ai_summary_test.exs`.

**Interfaces (produces):**
- `AiSummary.state(socket, cached :: %{summary: String.t()} | nil, request :: (-> term())) :: state() | :none`: `{:ok, text}` when cached; `:none` for a crawler; `:loading` before the page is live; `:limited` past the visitor's hourly limit; else `requested(request.())`. The request function runs only on the last branch.
- `AiSummary.load(socket, key :: atom(), kind :: atom(), {subject, input} | nil) :: socket`. It stops listening on the topic previously kept under `key` (in an `:ai_topics` map assign) and assigns `key` to `{subject, state}`, or to `nil` when there is nothing to show (no input, summaries disabled, or `:none`). When live and not cached, it listens on `Summaries.ai_topic(kind, subject)` before asking, and keeps the topic under `key` while the state is `:loading`.
- `AiSummary.put_result(socket, key, subject, result)`: assigns `{subject, result_state(result)}` when `key` still holds `subject`; otherwise the socket is unchanged.
- `AiSummary.report(assigns, kind, subject)` returns the map "Report a problem" sends: kind, subject, `Summaries.cache_version(kind)`, `assigns.path`, user and remote_ip. `AiSummary.prompt_url(kind)` returns the GitHub link (the one `@repo_url`).
- `result_state/1` and `requested/1` stay as they are. `load/2` (bill) stays for the home page, as `AiSummary.load(socket, bill)` → `{subject, state} | nil`.

- [ ] Tests first, using `%Phoenix.LiveView.Socket{}` built with and without a `transport_pid` (live / not live):
  - a cached summary returns `{:ok, text}` and never calls `request`;
  - a crawler returns `:none` without calling `request`;
  - a page that isn't live returns `:loading` without calling `request`;
  - past the limit returns `:limited`;
  - otherwise `requested(request.())` is returned (`:queued` gives `:loading`).
  - `put_result` ignores a result for another subject.
- [ ] Implement, then commit `refactor: AiSummary holds the shared summary decision`.

### Task 2: The four copies use it

**Files:** `bill_live.ex`, `rep_panel.ex`, `home_live.ex`, plus the templates that use `@repo_url`.

- [ ] Bill summary, change explanation and week summary use `AiSummary.load/4` and `put_result/4`. Remove `change_topic`, `week_topic`, the private `ai_state`/`requested` copies and `@hour`.
- [ ] Section summaries use `AiSummary.state/3`, with `cached = Summaries.get(version_id, i, text)` and `request = fn -> Summaries.request(version_id, i, text) end`. Their topics stay in the `summary_topics` list, since a section is listened to under its own topic, and their `{:section_summary, …}` messages stay as they are.
- [ ] `report/3` and `prompt_url/1` replace the three report maps and three `@repo_url`s.
- [ ] **The one fix:** the bill summary's topic is now released when the page moves to another version. Today it stays subscribed. Test: a bill page that switches version and then receives the old subject's result shows the new version's state.
- [ ] Run the full suite. Expected: every existing test passes unchanged. Commit `refactor: bill, reps and home pages get summaries through AiSummary`.

### Task 3: Search finds cached summaries without reading text

**Files:** `lib/everyday_citizen/search.ex:140-150, 337-344`; test `search_bills_test.exs`.

- [ ] Test first: a name search whose bills have cached summaries makes no query that selects `plain_text`. Use the telemetry watcher pattern from `home_live_test.exs` (`watch_text_queries`). Also check the existing test "a cached summary shows under its AI label" still passes.
- [ ] Implement `bills_by_name/2` so it looks up summaries for all its bills at once, with `Inputs.bill_subjects/1` and `Summaries.cached_ai(:bill, subjects)`, and remove `cached_summary/1`.
- [ ] Commit `perf: search finds cached bill summaries without reading bill text`.

### Final

- [ ] Whole-branch review by a fresh reviewer, the full suite, merge, CI green, then check a bill page and a search in production.
