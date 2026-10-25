# Bill Text History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every section of a bill's text shows where it came from (since introduced / changed / added), with the steps that changed it, the reader's reps' part, a marked-up comparison and an AI explanation of the change.

**Architecture:** The federal adapter adds three generic per-bill records (committee activity, related measures, amendments) to the bill sync. A domain module computes version lineage and comparisons from stored version sections and gathers each step's context. A new summary kind writes change explanations on view. BillLive renders origin tags, an origin panel and the comparison.

**Tech Stack:** Phoenix LiveView, Ecto, Oban, Req, Claude Haiku via the existing summary pipeline.

**Spec:** `docs/superpowers/specs/2026-10-25-bill-text-history-design.md`

## Global Constraints

- No UI or domain code names a legislature (boundary test bans congress, bioguide, senate, house, lis_member, crs); federal parsing lives in `lib/everyday_citizen/adapters/federal/`.
- Every stored record keeps its source (`source_id`).
- AI text: on view, cached (`ai_summaries`), budgeted, crawler-guarded, labeled "Written by AI from … ; it can be wrong", prompt published in `priv/prompts/`, never why.
- Facts are stated from the record ("considered adopted under H. Res. 1438", "no separate vote"), never characterized.
- Run `mix precommit` and `mix credo --strict`; append to `docs/DECISIONS.md`.

## Review Focus

1. A bill with one version, or versions without sections: no origin tags, no panel, no errors.
2. Two sections with the same heading, or a renumbered section: matched by heading then number, never crossing into another section's history.
3. A version with no date: ordered last, still compared.
4. A huge changed section (thousands of words): the comparison stays bounded (collapsed unchanged paragraphs; AI input capped by the existing writer).
5. A rep with no vote in a step: "no recorded vote" wording, not silence; Senate reps on a House-only change are told the Senate hasn't voted on it.

---

### Task 1: Ingest committee activity, related measures and amendments

**Files:** migration `create_bill_context` (`bill_committee_activities`: bill_id, body_id nullable, body_ref, kind, date, source_id; `bill_relations`: bill_id, related_bill_id nullable, related_ref, kind; `bill_amendments`: bill_id, external_id, identifier, description, latest_action, latest_action_date, url, source_id); schemas under `lib/everyday_citizen/legislation/`; `Records.BillCommittees`, `Records.BillRelations`, `Records.BillAmendments` (each replaces the bill's set); writer clauses in `Writer.Legislation`; `Normalize.BillContext` (federal); `SyncBill` fetches `/committees`, `/relatedbills`, `/amendments` (+ `/amendment/{c}/{type}/{n}` detail only when the latest action matches `/agreed to|adopted/i`); on-demand job `bill_history` enqueuing `SyncBill` for bills with two or more versions.

**Interfaces — Produces:** `Legislation.committee_activities(bill_id) :: [%{body, body_ref, kind, date}]` (kind ∈ referred markup reported other), `Legislation.related(bill_id, kind) :: [Bill.t()]`, `Legislation.amendments(bill_id) :: [BillAmendment.t()]`.

- [ ] Tests first (fixtures from the real H.R. 7008 responses): activities map `Referred To`/`Markup By`/`Reported By` to referred/markup/reported with the committee by code (`hsha00`), `Unknown` → other; relation `Procedurally related` → procedural (H. Res. 1438), others related; HAMDT 267 stored as "H.Amdt. 267" with its description and page `https://www.congress.gov/amendment/119th-congress/house-amendment/267`; a not-agreed amendment stored without a detail request. Implement; commit.

### Task 2: Version lineage and comparison

**Files:** `lib/everyday_citizen/bill_history.ex`, test.

**Interfaces — Produces:**
- `BillHistory.versions(bill) :: [%{code, classification, date}]` oldest first (nil dates last).
- `BillHistory.origins(bill, code) :: %{index => %{status: :original | :changed | :added, added_in: code | nil, changed_in: [code]}}` for the sections of `code`; `%{}` when fewer than two versions have sections.
- `BillHistory.comparison(bill, code, index) :: %{from: code, paragraphs: [[{:eq | :del | :ins, String.t()}]]} | nil` against the latest earlier version where the section differed; nil for unchanged or added.
- Section key: normalized heading (lowercase letters only), else `"#" <> enum`; text: flattened block text, whitespace-normalized. Paragraph alignment with `List.myers_difference` on paragraph texts, word-level `String.myers_difference`-style diff within changed pairs; unchanged paragraphs returned as a single `{:eq, "…"}` marker run (collapsed by the UI).

- [ ] Tests first from H.R. 7008-shaped fixtures (ih, rh, eh versions): Sec. 1 :original; Sec. 2 :changed with changed_in ["rh", "eh"]; Sec. 3 :added in "eh"; the rh comparison of Sec. 2 marks `—` and `; and` deleted and `.` inserted; one-version bill → `%{}`; duplicate headings matched in order. Implement; commit.

### Task 3: What produced each version, and reps' part

**Files:** `BillHistory.steps/1`, `BillHistory.involvement/3`, test.

**Interfaces — Produces:**
- `BillHistory.steps(bill) :: [%{code, classification, date, from_date, actions: [BillAction], committees: [activity], amendments: [BillAmendment], votes: [Vote], related_votes: [{Bill, Vote}]}]` — each version's window is (previous version's date, its date]; amendments by latest action date; related votes are votes on `related(bill, "procedural")` measures in the window.
- `BillHistory.involvement(step, people :: [Person], memberships) :: [%{person, votes: [{Vote, option}], committees: [Body]}]`.

- [ ] Tests first: H.R. 7008's "eh" step holds H.Amdt. 267, the H. Res. 1438 votes (254, 253) and passage 280; the "rh" step holds the House Administration markup; a rep on that committee gets it in `committees`; a rep with no position gets `votes: []`. Implement; commit.

### Task 4: AI explanation of a change

**Files:** `priv/prompts/change_summary.v1.md`; `Claude` kind `:change` (tag `<change>`, 400 tokens); `Summaries.prompt_versions` `change: "v1"`; `Inputs.change(bill, code, index) :: {"change:<bill_id>:<code>:<key_hash>", input} | nil` (input: `<before>…</before><after>…</after>`, or `<added>…</added>`); `Inputs.input("change", subject)` rebuilds it; `SummarizeSubject` accepts kind "change".

- [ ] Tests first: input for Sec. 2 rh holds both texts; for Sec. 3 eh only `<added>`; unchanged section → nil; subject rebuild round-trips; job writes and broadcasts. Implement; commit.

### Task 5: Bill page — origins, panel, comparison, explanation

**Files:** `bill_live.ex`, `floor_components.ex` (origin tag, origin panel), tests.

- [ ] Tests first (LiveView): section headers show "Since introduced" / "Changed … · <date>" / "Added <date>"; opening Sec. 3 shows "Where this section came from" with H.Amdt. 267's description and link, "considered adopted" definition, and the rule's vote; with district OH-like fixture, a rep's Yea on the rule shows with its roll-call link; a rep on the committee shows "Sits on the committee"; opening Sec. 2 shows deleted/inserted marks and the AI box (cached) labeled "Written by AI from the two versions"; crawler starts no change summary; one-version bill shows no tags. Implement; visual check 390/1440; commit.

### Task 6: Record and roll out

- [ ] DECISIONS entry; CLAUDE.md milestone note; `mix precommit`, credo; final review (most capable model) with this Review Focus; fix pass; merge; deploy; run `bill_history` backfill (check DB disk first); confirm H.R. 7008 in production.
