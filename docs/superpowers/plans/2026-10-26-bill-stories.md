# Bill Stories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every bill summary leads with "If this becomes law": up to 4 groups, one plain sentence each, with the rest of the summary folded below.

**Architecture:** A new prompt version (`bill_summary.v4`) adds a `## If this becomes law` part to the same Claude reply. A pure parser, `EverydayCitizen.Summaries.Story`, splits a stored reply into groups, the example and the rest. Three surfaces render from it: the bill page (all group cards and folds), home's new laws (first group plus "+N more groups") and search results (first group). Each falls back to today's rendering when no groups parse.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx function components in `floor_components.ex`.

**Spec:** `docs/superpowers/specs/2026-10-26-bill-stories-design.md`

## Global Constraints

- No federal words in `lib/**/*.ex` outside the adapter (congress, senate, house, bioguide, crs, lis_member), comments and HEEx included (`boundary_test.exs`).
- Copy never names the legislature.
- AI text always carries "Written by AI from …; it can be wrong" and the prompt link; the bill's text stays on the page.
- Crawlers never start a summary; search never starts one; non-summary surfaces (person, reps, this week, settings, email) are untouched.
- Tests never call outside services (Req.Test stubs only).
- Phone first; nothing scrolls sideways at 400px.
- `mix precommit` and `mix credo --strict` clean before each commit; commit trailer as in CLAUDE.md's session rules.
- Append to `docs/DECISIONS.md`; never rewrite it.

## Ruling made while planning

- The spec says the new part comes "first in the same reply". The plan puts `## If this becomes law` **last** in the reply and shows it first on the page. Why: v3's first part is the unheaded summary, and the parser, the length-band rule and `Writer.drop_length_echo/1` all key on that. Writing the story after the full summary also lets the model distill it. Cost if wrong: one prompt edit to move the part, with the parser unchanged, since it finds the part by heading.

## Review Focus

1. A group line with no ": " or with an empty sentence: it must be skipped, not shown as a blank card (Task 1 test).
2. More than 4 group lines: only the first 4 are shown (Task 1 test).
3. A v3-shaped reply, with no story part, on all three surfaces: today's rendering, unchanged (Tasks 3 and 4 tests).
4. "+1 more group" and "+2 more groups" plural forms, and no link with one group (Task 4 test).
5. The "Report a problem" form still receives the whole reply (Task 3 test).

---

### Task 1: The story parser

**Files:**
- Create: `lib/everyday_citizen/summaries/story.ex`
- Test: `test/everyday_citizen/summaries/story_test.exs`

**Interfaces:**
- Produces: `EverydayCitizen.Summaries.Story.split(text :: String.t()) :: %{groups: [%{label: String.t(), sentence: String.t()}], example: String.t() | nil, rest: String.t()}`
  - `groups`: from the `## If this becomes law` part, each `- label: sentence` line split on the first ": ", both trimmed. Lines missing either side are skipped. At most 4. `[]` when the part is absent.
  - `example`: the body of `## For example`, trimmed, or nil.
  - `rest`: the text with both parts (heading and body) removed, trimmed, keeping every other part and its `## ` heading in order.
- Produces: `Story.heading() :: "If this becomes law"` (the prompt test uses it).

- [ ] **Step 1: Write the failing tests** in `story_test.exs` (`use ExUnit.Case, async: true`):
  - `"splits the groups, the example and the rest"`: input is
    `"It warns members.\n\n## Who this affects\n- Apps: send warnings.\n\n## Words to know\n- Fraud ban: an ended account.\n\n## For example\nMade-up situation: an app bans an account.\n\n## If this becomes law\n- If you use a dating app: you'd be warned within a day.\n- If you run a dating app: you'd send the warnings."`.
    Assert `groups == [%{label: "If you use a dating app", sentence: "you'd be warned within a day."}, %{label: "If you run a dating app", sentence: "you'd send the warnings."}]`, `example == "Made-up situation: an app bans an account."`, and `rest == "It warns members.\n\n## Who this affects\n- Apps: send warnings.\n\n## Words to know\n- Fraud ban: an ended account."`.
  - `"a reply without the part has no groups and keeps its text"`: for `"It does one thing.\n\n## Who this affects\n- People: x."`, assert `groups == []`, `example == nil`, and `rest` equals the input.
  - `"lines without a label or a sentence are skipped, and at most four are kept"`: the part holds `- No colon here`, `- Empty:`, then six valid `- G1: s1.` … `- G6: s6.`. Assert the labels are `["G1", "G2", "G3", "G4"]`.
  - `"only the first colon splits"`: `- State officials: they could sue: in federal court.` gives `sentence == "they could sue: in federal court."`.
- [ ] **Step 2: Run** `mix test test/everyday_citizen/summaries/story_test.exs`. Expected: FAIL (module `Story` not available).
- [ ] **Step 3: Implement `Story.split/1` and `Story.heading/0`.** Split on `^##[ \t]+(.+)$` lines, as `floor_components.ex`'s `summary_sections/1` does. A moduledoc says this is the stored reply's shape from `priv/prompts/bill_summary.v4.md`.
- [ ] **Step 4: Run** the same command. Expected: 4 tests, 0 failures.
- [ ] **Step 5: Commit** `feat: parse a bill summary's story part`.

### Task 2: Prompt v4

**Files:**
- Create: `priv/prompts/bill_summary.v4.md` (a copy of v3 plus the new part)
- Modify: `config/config.exs:60` (`bill: "v4"`), `lib/everyday_citizen/summaries/writer.ex` (`@bands` caps)
- Modify tests: `test/everyday_citizen/summaries/claude_test.exs:79` (`"bill_summary.v4.md"`), `test/everyday_citizen/summaries/writer_test.exs` (band caps), `test/everyday_citizen_web/components/ai_box_test.exs:59` (v4, plus `"## " <> Story.heading()` in the heading list)
- Modify: `docs/DECISIONS.md` (append)

**Interfaces:**
- Consumes: `Story.heading/0`.

- [ ] **Step 1: Update the tests first.** The prompt test reads `bill_summary.v4.md` and also asserts `prompt =~ "## If this becomes law"`. The Claude test expects `bill_summary.v4.md`. The writer band test expects `{"short", 1100}`, `{"medium", 1400}`, `{"long", 1800}`, `{"very long", 2200}`, and the short-bill test's `max_tokens == 1100`.
- [ ] **Step 2: Run** `mix test test/everyday_citizen/summaries test/everyday_citizen_web/components/ai_box_test.exs`. Expected: FAIL (missing file, old caps).
- [ ] **Step 3: Write `bill_summary.v4.md`.** Change v3's "four parts" to five and "all four parts" to all five. Add this part last, before "Rules for every part", with the text exactly as follows:

```
## If this becomes law
Last, the story of the bill from each side: 1 to 4 bullet points, one for each
group of people or organizations the bill most directly affects, most
affected first, and people before agencies when the bill names both. Each is
"- ", a short plain label for the group in the bill's own terms, a colon, and
one sentence saying what the bill would require of them, allow them or give
them. Write the label and sentence to the reader ("If you use a dating app:
you would get…") when the group is people a reader could be; otherwise name
the group ("State attorneys general: they could…"). A bill that names no
people still has one group: what it names, such as a building or an agency.
Give no names, ages or places, and no effects the bill does not state.
```

  Also change the final line to "Reply in plain text with only the five parts and their headings…". Raise the caps in `@bands` to 1100/1400/1800 and very long to 2200, and update the reply-cap comment. Set `bill: "v4"` in config.
- [ ] **Step 4: Append to DECISIONS.md:** `## 2026-10-26 — Bill summaries lead with "If this becomes law"`. One paragraph: prompt v4 adds up to 4 groups with one sentence each, written last in the reply and shown first; caps rise by 200 tokens per band; every cached bill summary is rewritten on its next view, inside the budget; the owner reviewed real output before it shipped.
- [ ] **Step 5: Run** the Step 2 command. Expected: PASS.
- [ ] **Step 6: Commit** `feat: bill summary prompt v4 tells the story group by group`.

### Task 3: The bill page leads with the groups

**Files:**
- Modify: `lib/everyday_citizen_web/components/floor_components.ex` (new `bill_story/1`; extract the `{:ok, text}` body of `ai_box` into a private `summary_body/1` that both use)
- Modify: `lib/everyday_citizen_web/live/bill_live.ex:726-741`
- Test: `test/everyday_citizen_web/live/bill_live_test.exs` (the "executive summary" describe block, around line 455)

**Interfaces:**
- Consumes: `Story.split/1`.
- Produces: `bill_story/1` with the same attrs as `ai_box` (`id`, `class`, `title`, `source`, `state`, `prompt_url`, `report`). For `{:ok, text}` with groups:
  - h2 "If this becomes law";
  - one card per group (label bold, then the sentence); the first card carries `border-2 border-floor-accent`, the rest `border border-floor-line`;
  - the AI label line and prompt link, worded as `ai_box` words them;
  - `<details id={@id <> "-example"}>` "A made-up example" (only when `example` is set; rendered as the dashed example box);
  - `<details id={@id <> "-full"}>` "The full summary" (`rest` through `summary_body`);
  - the `FeedbackForm` with the whole `text`.

  Both `<details>` are closed, use `disclosure_mark` and `phx-mounted={JS.ignore_attributes(["open"])}`, with summary rows at least 44px tall. Every other state, or no groups, renders `ai_box` exactly as today.

- [ ] **Step 1: Write the failing tests:**
  - `"the summary leads with each group's story and folds the rest"`: cache the Task 1 sample reply for the bill and open `/bills/119-s-5`. Assert:
    - `has_element?(view, "#bill-summary h2", "If this becomes law")`;
    - `has_element?(view, "#bill-summary", "If you use a dating app")`;
    - `has_element?(view, "#bill-summary-example:not([open])", "Made-up situation")`;
    - `has_element?(view, "#bill-summary-full:not([open])", "Who this affects")`;
    - `has_element?(view, "#bill-summary", "Written by AI from the bill")`;
    - the html contains "If this becomes law" before "Text of the bill".
  - `"a summary without a story part shows as before, open"`: the existing test "a cached executive summary sits above the bill's text" still passes unchanged; also `refute has_element?(view, "#bill-summary-full")`.
  - `"a problem report carries the whole summary, story included"`: with the sample cached, submit the report form, following the pattern of the existing FeedbackForm test in this file. Assert that the stored report's summary contains "## If this becomes law" and "## Who this affects".
- [ ] **Step 2: Run** `mix test test/everyday_citizen_web/live/bill_live_test.exs`. Expected: the new story tests FAIL; all others pass.
- [ ] **Step 3: Implement `bill_story/1`, and switch the bill page's `<.ai_box id="bill-summary" …>` to `<.bill_story …>`** with the same attrs. Change the section's `aria-label` to "If this becomes law".
- [ ] **Step 4: Run** the Step 2 command, then `mix test test/everyday_citizen_web/components`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: the bill page leads with what the bill would do for each group`.

### Task 4: Home cards and search results show the first group

**Files:**
- Modify: `floor_components.ex` (new `story_line/1`)
- Modify: `lib/everyday_citizen_web/live/home_live.ex:293-303`, `lib/everyday_citizen_web/live/search_live.ex:290-298`
- Test: `test/everyday_citizen_web/live/home_live_test.exs`, `test/everyday_citizen_web/live/search_live_test.exs`

**Interfaces:**
- Consumes: `Story.split/1`.
- Produces: `story_line/1`, with attrs `id`, `group :: %{label, sentence}`, `more :: non_neg_integer()` and `href :: String.t()`. It renders:
  - the label bold, then the sentence;
  - when `more > 0`, a link to `href` reading "+1 more group" or "+N more groups";
  - the small label "Written by AI from the bill; it can be wrong".
  - Home renders `story_line` when the summary state is `{:ok, text}` and there are groups. Otherwise it renders the clamped `ai_box`, as today.
  - Search renders `story_line` (`more` 0, no link) when the result's summary has groups. Otherwise it renders `opening/1`, as today.

- [ ] **Step 1: Write the failing tests:**
  - home: `"a law's card shows its first group and how many more"`. `cache!(1, sample)` with three valid groups. Assert:
    - `has_element?(view, "#law-summary-<external_id>", "If you use a dating app")`;
    - a link `a[href="/bills/<external_id>"]` with "+2 more groups";
    - no "Made-up situation" on the page.
  - home: `"one group, no more link"`: assert no "more group" text.
  - home: the existing tests with plain cached summaries ("Cached.", "It names a post office.") still pass unchanged.
  - search: `"a result with a story shows its first group"`: cache the sample for a bill the query finds. Assert the group's label and sentence are shown, and "It warns members." is not. The existing opening-paragraph test still passes.
- [ ] **Step 2: Run** `mix test test/everyday_citizen_web/live/home_live_test.exs test/everyday_citizen_web/live/search_live_test.exs`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** `story_line/1` and the two call sites.
- [ ] **Step 4: Run** the Step 2 command, then the full `mix precommit` and `mix credo --strict`. Expected: all pass and no credo issues.
- [ ] **Step 5: Visual check.** Take headless Chrome screenshots of a bill page and `/` at 400px and 1280px, using the temporary `priv/static/images/zz-frame.html` iframe and deleting it afterwards. Use local cached v4 summaries from Task 5, or a temporary local `put_ai` of the sample. Confirm nothing scrolls sideways.
- [ ] **Step 6: Commit** `feat: home and search show a bill's first group`.

### Task 5: Real output, reviewed by the owner (gate before merge)

**Files:** none in the repo. The script and output go in the session scratchpad.

- [ ] **Step 1: Write the script.** It runs with `mix run --no-start` and starts only what `Writer.write/2` needs, as `Mix.EverydayCitizen.start_without_workers()` does. It uses the local `ANTHROPIC_API_KEY` from `.env`; never print the key. For 8 local bills it calls `Writer.write(:bill, text)` and saves each with `Summaries.put_ai`, so the visual check can use them. The 8 are H.R. 2481, H.R. 227 and H.R. 4107, a bill that became law (`Legislation.recent_laws(1, 0)`), a ceremonial naming bill (title matching "post office" or "designate"), and three others of different sizes. It writes each bill's identifier, title and story part to `bill-stories-sample.md` in the scratchpad.
- [ ] **Step 2: Run it** and check the day's spend with `Summaries.spent_today_usd()`. Expected: under $1.
- [ ] **Step 3: Show the owner** the 8 stories, as a page or in chat, and flag any line that breaks a rule: a name, an argument, an effect the bill doesn't state, or a wrong order of groups.
- [ ] **Step 4:** If the owner asks for prompt changes, edit `bill_summary.v4.md` (it is unpublished, so editing it in place is fine), re-run, and show the stories again. Merge, push and deploy only after the owner approves.
