# Bill stories: what a bill would do, group by group, first

_Design, 2026-10-26. Mockup (option C, and the home card):
https://claude.ai/artifact/JTQQ97GneLon2iStSFXtBf_

## Why

The owner finds every bill summary too dense. Most visitors give a bill a
moment or two of attention, so the first thing they see has to be the meat:
enough that they could tell a story about what the law would do to people. The
full summary stays, one tap away, for anyone who wants to learn more.

The owner chose to tell that story from each affected group's side ("If you use
a dating app…", "If you run a dating app…"), so a reader can think about the
bill from each group's point of view, and it is easy to take in at a glance.

## Goals

- A new top part of every bill summary, **"If this becomes law"**: up to 4
  groups the bill affects, each with one plain sentence on what would change
  for them.
- It is what a reader sees first wherever a bill summary is shown today.
- The rest of the summary (the summary itself, who this affects, words to know,
  the made-up example) is still there, folded away below.

## Non-goals

- No story where no summary is shown today. Person pages, the reps page, this
  week's schedule, followed bills in settings and the daily email keep showing
  bills as titles and links. Seeing a list never starts writing summaries.
- No separate treatment for laws: a bill that became law behaves exactly like
  any other bill.
- No change to section summaries, change explanations, the rep's week summary,
  the budget or the per-visitor limit.

## Anti-goals (a failure even if it works)

- A story that argues: benefits, harms, motives, predictions or effects the
  bill does not state. The existing prompt rules apply to this part too.
- A story that invents a person: no names, ages, places or other details.
  (One cached v3 example named "Maria" despite the rule; the new part must not
  do this.)
- Copy that names the legislature, or UI/domain code that knows it is federal.
- A story shown without its source: the AI label and prompt link stay, and the
  bill's text stays on the page.

## What the reader sees

### Bill page

Right under the bill's identifier, status and title:

1. Heading **"If this becomes law"**.
2. One card per group, in the order the summary gives them: the group in bold
   as a short plain label, then its one sentence. The first card is set apart
   (the mockup's accent border).
3. The usual label: "Written by AI from the bill's text; it can be wrong", with
   the link to the published prompt.
4. Folded below (closed by default, `<details>` with the site's ▸/▾
   `disclosure_mark`): **"A made-up example"**, then **"The full summary"**
   (the summary, who this affects, words to know).
5. The bill's text and its section summaries, as today.

The loading, limited, paused and unavailable states are unchanged; they take
the place of the cards.

### Home page, new laws

Each law's card shows the first group's line (label and sentence) in place of
today's clamped summary, then "+N more groups" linking to the bill page when
there are more. Loading and limit behaviour as today.

### Search results

Where a result shows a cached summary's opening today, it shows the first
group's line instead. Search still never starts a summary.

## How the story is written

- One Claude call, as now: a new version of the published prompt,
  `priv/prompts/bill_summary.v4.md`, puts the new part first in the same reply.
  The other parts and their rules carry over from v3 unchanged.
- The new part's shape, so it can be parsed reliably: the heading line
  `## If this becomes law`, then up to 4 bullet lines `- <group>: <sentence>`.
  - The group is a short plain label for people or organizations the bill
    names, in the bill's own terms.
  - Most directly affected first; people before agencies when the bill names
    both.
  - Second person ("you") when the group is people a reader could be;
    third person for agencies, officials and companies.
  - One sentence per group, saying only what the bill would require, allow or
    give them.
- The length band applies to the summary part only, as today.
- The prompt-version change means every cached bill summary is written again
  the first time someone views it, inside the daily budget and visitor limit
  (owner accepted, 2026-10-26).
- The drop of a restated length line (`Writer.drop_length_echo/1`) stays.
- **The owner reviews real output before it ships** (owner, 2026-10-26):
  before deploying, run the v4 prompt locally on about 8 varied bills (H.R.
  2481, H.R. 227, H.R. 4107, a bill that became law, a ceremonial naming bill
  and a few others), well under $1 on the development API key, and show the
  owner the stories. The prompt ships only after the owner approves them.

## Constraints

- Every rule in CLAUDE.md: no federal words outside the adapter
  (`boundary_test.exs`), copy never names the legislature, AI text always
  beside its source and labeled, prompts published, crawlers never start a
  summary, tests never call outside services.
- Phone first, as in the mockup; nothing scrolls sideways at 400px.
- Record the prompt change in `docs/DECISIONS.md` (append).

## Calls made on the builder check (mine; the owner can overrule)

- **A cached v3 summary is a miss**, as any prompt-version change is today:
  the page shows "loading" while v4 is written, and does not show the v3 text.
- **Every bill has at least one group.** The prompt says so: a bill that names
  no people (a ceremonial naming bill, say) gets one line for what it names,
  such as the building or the agency. Zero groups only happens when the model
  breaks the rule, which is the unparsed fallback.
- **Unparsed on the home page and in search:** show today's summary opening
  (the clamped summary on the home card, `opening/1` in search). With one
  group there is no "+N more groups" line.
- **Headings:** the stored text keeps v3's `## Who this affects`,
  `## Words to know` and `## For example` (so `ai_box`'s example styling still
  keys on it); the page relabels the example fold "A made-up example". "The
  full summary" fold holds the summary, who this affects and words to know;
  the example is its own fold, above it.
- **Report a problem** still receives the whole reply, story included.
- **Mockup details**, for anyone who cannot open it: each group is a white
  card (`floor-card`, 12px radius, 14px by 16px padding), the label bold on its
  own line and the sentence under it; the first card has a 2px `floor-accent`
  border and the rest the usual 1px line; the folds are full-width rows at
  least 44px tall.

## Left to the builder

- Parsing: extend the existing `summary_sections/1` split (it already splits
  on `## ` headings) and a small parser for `- group: sentence` lines; one
  shared function the three surfaces use.
- A reply with no "If this becomes law" part, or none that parses: show the
  summary as today, opened rather than folded (my call).
- Search results for bills whose only cached summary is v3: show no line
  until it is rewritten (my call; search never writes).
- Markup and exact spacing, following the mockup and the site's components
  (`ai_box`, `floor-card`, `floor-accent`).
