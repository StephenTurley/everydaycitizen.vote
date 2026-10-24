# M3b: Bill Executive Summaries, Weekly Rep Summaries, Shorter Section Summaries — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every bill page shows a plain-English executive summary above the bill text; the reps page gets a week switcher and a plain-English summary of what the selected rep did that week; section summaries get shorter.

**Architecture:** Builds on M3 (`docs/superpowers/plans/2026-10-24-m3-plain-language-summaries.md`): the same Claude client and credentials, on-view generation, unique jobs, PubSub delivery, cache keyed by what was summarized (a `source_hash`), and the shared daily budget. Bill and week summaries live in one new table `ai_summaries` keyed by `(kind, subject, prompt_version)`; section summaries stay in `section_summaries`.

**Tech Stack:** as M3 (Phoenix LiveView, Oban, Req, Claude Haiku 5.5, no `temperature`).

**Spec:** the owner's direction of 2026-10-24: "an executive summary should always appear above the bill text"; "summarize what each rep did for the week that is viewed" on the reps page (where a rep is already selected), confirmed with the design "week switcher under the rep's name, the feed shows that week, a summary at the top"; plus the M3 rules (on view, cached, budgeted, plain English a high school student could follow, never why).

## Global Constraints

- All of M3's: summaries shown with their source (bill text below; the week's feed below), labeled "Written by AI from the … below; it can be wrong" with a link to the published prompt; only what the record or text says; no reasons, opinions, predictions, parties or motives; no legislature named in prompts or UI; output escaped.
- Prompts published under `priv/prompts/`: `section_summary.v2.md` (shorter), `bill_summary.v1.md`, `rep_week.v1.md`. Config `:summaries, prompt_versions: %{section: "v2", bill: "v1", rep_week: "v1"}` replaces `prompt_version`.
- Shared budget in dollars (owner, 2026-10-24): every Claude call records its input/output tokens in `ai_usage` (kind, tokens, cost in micro-dollars at the configured rates: $0.10/M input, $0.50/M output up to 100K input tokens per request, $0.50/$2.50 above); new summaries pause once today's spend reaches `daily_budget_usd` (default 2.00). This replaces M3's count-based `daily_limit`. Per-visitor limit 30/hour covers every kind; one unique job per subject at a time.
- Bill input: every bill is summarized from its latest version's full text (owner, 2026-10-24: large bills too). Up to 250,000 characters: one request. Larger: split at section boundaries into chunks of ≤ 250,000 characters (each under the 100K-token tier), each chunk summarized (`bill_chunk.v1.md`, a few bullets), then one final call writes the executive summary from the chunk summaries in order. No text at all: no box.
- Proportional length (owner): the summary scales with the bill. Size bands by full-text characters: short ≤ 10,000 (2–3 sentences, `max_tokens` 300); medium ≤ 60,000 (3–5 sentences or up to 5 bullets, 500); long ≤ 250,000 (a 2–3 sentence overview plus up to 8 bullets, 900); very long > 250,000 (overview plus up to 12 bullets, grouped by the bill's major parts where it has them, 1,400). The band is passed to the model in the user message ("Length: short") and the prompt defines each band.
- Week input: the selected rep's activity items in that week (America/New_York, Monday–Sunday), each a line with date, kind, bill identifier and title, and for votes the question, result and the rep's position. No items: "Nothing on the record for this week." and no call.
- Week URL: `/reps/:district?rep=<id>&week=YYYY-MM-DD` (Monday); default the current week; the existing `filter` param still applies within the week.

## Review Focus

1. A bill whose latest version changes (new text) after its summary was cached: the old summary is not shown; the next view writes one from the new text.
2. The current week gains a vote after its summary was cached: the next view sees a different input hash and writes a fresh summary; past weeks stay cached.
3. A bill with no text versions, or a rep week with no activity: no AI call, the right empty state.
4. A 3-million-character bill: chunked so no request exceeds 250,000 characters, each chunk summarized, then combined; the day's dollar budget is checked before each call so a huge bill cannot run far past it.
5. Week navigation to the far future or a malformed `week=`: falls back to the current week, no crash, no call.

---

### Task 1: Shorter section summaries and one client for all prompts

**Files:** create `priv/prompts/section_summary.v2.md`; modify `lib/everyday_citizen/summaries/claude.ex` (`summarize(text, kind)`), `lib/everyday_citizen/summaries.ex`, config, tests.

**Interfaces:**
- `Claude.summarize(text :: String.t(), kind :: :section | :bill | :rep_week) :: {:ok, result} | {:error, term}` — system prompt `priv/prompts/<kind>_summary|rep_week.<version>.md` per `prompt_versions`; `max_tokens` 300 for `:section`, 500 for `:bill`, 300 for `:rep_week`; the user message wraps the input in `<section>`, `<bill>` or `<activity>` tags.
- `Summaries.prompt_version(kind)`; section summaries key on `prompt_version(:section)` ("v2"), so v1 summaries are regenerated on next open.
- `section_summary.v2.md`: as v1, but "at most 3 short sentences; for a section that does several things, up to 4 bullet points of one sentence each; leave out cross-references, table-of-contents updates and clerical changes".

- [ ] Tests first: the request carries the kind's prompt file and tag and max_tokens; a v1-cached section is not returned under v2. Implement; commit.

### Task 2: Generic summary store and job

**Files:** migration `create_ai_summaries` (`kind` string, `subject` string, `prompt_version`, `model`, `source_hash` binary, `summary` text, tokens, timestamps; unique `(kind, subject, prompt_version)`); `lib/everyday_citizen/summaries/ai_summary.ex`; `lib/everyday_citizen/jobs/summarize_subject.ex`; extend `Summaries`.

**Interfaces:**
- `Summaries.get_ai(kind, subject, input) :: AiSummary.t() | nil` (matching `source_hash`), `put_ai(kind, subject, input, result)`, `request_ai(kind, subject, input, topic_suffix) :: {:cached, s} | :queued | :paused | :disabled | :too_long` (same guards; `:too_long` over 60,000 characters of input), `ai_topic(kind, subject)`.
- `SummarizeSubject` job args `%{"kind", "subject", "prompt_version"}`, unique on those keys; it rebuilds the input itself (`Summaries.input(kind, subject)`), re-checks budget, calls Claude, stores, broadcasts `{:ai_summary, kind, subject, {:ok, text} | {:error, :unavailable | :paused}}`.
- `created_today/0` counts both tables.

- [ ] Tests first: one job for two simultaneous requests; budget re-check cancels; input change misses the cache. Implement; commit.

### Task 3: Bill executive summary above the text

**Files:** `lib/everyday_citizen/summaries/inputs.ex` (`bill_input(bill) :: String.t() | nil`, subject `"bill:<bill_id>:<version_code>"`), `priv/prompts/bill_summary.v1.md`, `lib/everyday_citizen_web/live/bill_live.ex`.

**Interfaces:**
- On connected mount, `request_ai(:bill, subject, input)`; the box "In plain English: what this bill does" sits directly above "Text of the bill" (both layouts), with loading / paused / unavailable / no-text states as M3.
- `bill_summary.v1.md`: what the bill would do if it became law, in plain English a high school student could follow; the main changes first; length by the band given (see Global Constraints); for chunk summaries as input, combine them into one summary of the whole bill.

- [ ] Tests first: a short bill is one request with "Length: short" and max_tokens 300; a 300,000-character bill is chunked at section boundaries (each chunk ≤ 250,000 characters) then combined, with "Length: very long" (Review Focus 4); cached summary shows above the text; new version text misses the cache (Focus 1); no versions shows no box (Focus 3); spend over the daily budget pauses new summaries. Implement; visual check at 390/1440; commit.

### Task 4: Week view and weekly summary on the reps page

**Files:** `lib/everyday_citizen/activity.ex` (`feed/2` gains `from: Date, to: Date`), `Inputs.rep_week_input(person, week_start) :: String.t() | nil`, `priv/prompts/rep_week.v1.md`, `lib/everyday_citizen_web/live/reps_live.ex`.

**Interfaces:**
- Week switcher below the rep's name ("Oct 19 – 25", ‹ › links keeping `rep` and `filter`; › hidden past the current week); the feed shows that week only; summary box at the top of the week, subject `"rep_week:<person_id>:<YYYY-MM-DD>"`.
- `rep_week.v1.md`: what this representative did on the record that week, in plain English; counts and the notable items (bills they introduced, how they voted on passage of bills, their bills that moved); 2–4 sentences; never why; never praise or criticism.

- [ ] Tests first: `week=` selects that week's items only; malformed or future `week=` falls back to the current week (Focus 5); a week with no items shows the empty line and queues nothing (Focus 3); a new vote in a cached week misses the cache (Focus 2); the input lists each item with the rep's position. Implement; visual check; commit.

### Task 5: Record and roll out

- [ ] DECISIONS: the three summaries, the outline rule for long bills, the shared budget; CLAUDE.md milestone note.
- [ ] `mix precommit`, `mix credo --strict`, final whole-branch review (most capable model), fix pass, merge, deploy (blue-green), and confirm in production: a bill page shows its executive summary; a rep's week shows a summary.
