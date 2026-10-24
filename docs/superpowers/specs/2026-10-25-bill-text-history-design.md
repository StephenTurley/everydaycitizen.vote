# Bill text history ("git blame for law") — design

Date: 2026-10-25. Owner direction in conversation; mockup:
https://claude.ai/artifact/9xiJE2P74WD7bcjznA1BRa (desktop: a changed section;
phone: an added section).

## Why

A reader of H.R. 7008 (Stop Insider Trading Act) could not tell that its voter
photo ID section was not in the bill as introduced or reported, but arrived in
a Rules Committee substitute that was "considered adopted" under the rule
H. Res. 1438, with no separate vote on it. The owner wants the text itself to
carry its origin, "git blame for law", with the reader's own reps' part in each
change and a plain-English explanation of what each change does.

## What the reader gets

1. **Origin on every section** of the version being read: "Since introduced"
   (quiet, gray), "Changed in committee · Feb 3" / "Changed · Jul 22" (amber),
   "Added Jul 22" (teal). Shown in the section list and contents rail.
2. **Where this section came from**, inside an opened section that changed or
   was added: a timeline of the steps that touched it, each with its date, what
   produced that version (committee activity, agreed amendments with their
   official description and link, procedurally related measures such as the
   rule, and roll-call votes in that window), and folded plain definitions
   ("considered adopted", "marked up", "amendment in the nature of a substitute").
3. **Your reps and this section**: for the reader's reps (district known), at
   each step: their votes on the bill and on its procedurally related measures in
   that step's window (with roll-call links), and membership of a committee that
   acted in that window. A rep with no part says so ("hasn't voted on this
   section"). Committee members' individual markup votes are not in our sources;
   say so where a committee step is shown.
4. **The change in the text**: an opened changed section shows the previous
   version's wording against this version's, deletions and insertions marked,
   paragraph by paragraph (unchanged paragraphs collapsed), with "Show the
   whole section".
5. **In plain English: what this change does**: an AI explanation of one
   section's change between two versions (or of an added section), written
   from those texts only, beside them, labeled "Written by AI from … ; it can be
   wrong", with prompt link and Report a problem. Never why, never who it helps.
6. **How the text changed** strip under the title: the versions in order with
   date and what produced each (reuses the version picker's versions).

## Rules (from CLAUDE.md, binding)

- No UI or domain code knows it is federal: committee activities, related
  measures and amendments are generic records written by the federal adapter.
- Every record carries provenance; summaries are shown beside their source;
  the product states recorded facts and never motives.
- AI explanations: on view, cached, inside the daily budget; crawlers never
  start one.

## Data

- **Committee activity per bill** (referred, markup, reported, with dates;
  committee body by its code).
- **Related measures per bill** with kind `procedural` (e.g. the rule) or
  `related`.
- **Amendments per bill**: identifier, official description/purpose, latest
  action text and date, official page. Detail is fetched only for amendments
  whose latest action shows them agreed to or adopted.
- Version lineage is computed from stored version sections (matched by
  normalized heading, else number), not stored.

## Decided

- Sections are the unit of origin (not sentences); word-level marks only in the
  opened section's comparison.
- The origin panel sits inside the opened section on every screen size (the
  mockup's desktop side panel is a later refinement).
- No address: history without the reps layer.

## Left to the builder

Exact matching thresholds, layout details within the site's existing style.
