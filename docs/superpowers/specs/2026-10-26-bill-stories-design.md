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

---

## Revision, 2026-10-26: kinds of bill, unrelated parts, and where parts came from

Found on the sample review: telling every bill "people first" distorts bills
whose main effect is not on people. The GOLDEN DOME Act's story led with
lawsuits and procurement rules and left out its $23 billion authorization for
a defense program. And H.R. 7008 was only stock-trading rules as introduced,
but its passed version also requires photo ID to vote; a story that leads with
stock trading hides the second part.

### The rule above every other (owner, 2026-10-26)

**Simple lines lead, details follow.** Whatever the kind, the reader first sees
a few short, plain lines (at most 4, at most 20 words each); everything else
stays folded below, as in the first design.

### Kinds of bill (owner approved, 2026-10-26)

Built from a blind sample of 150 bills of the current session (stratified by
type, plus laws and bills that passed a chamber), then checked on 48 and 50
fresh bills. Claude picks one kind per **version** of a bill, from what that
version's text does, never from guesses about anyone's aim. The kind's label
shows beside the bill's title wherever its story shows (bill page, home cards,
search results).

| # | Label | Covers | The story leads with |
|---|---|---|---|
| 1 | Sets rules | requires, bans or allows something for people, businesses or officials; crimes, disclosure, conduct rules, conditions on federal money | who must, may or can't do what; then penalties, enforcement, start |
| 2 | Changes benefits | who qualifies for or gets a benefit, coverage, loan, payment, federal pay or immigration status | who gains or loses, what changes, from when |
| 3 | Changes taxes | taxes, credits, deductions, exclusions, tariffs | who pays more or less, on what, how much, from when |
| 4 | Funds the government | spending bills, stopgaps, shutdown pay | the total, the largest amounts and agencies, the period, limits on use |
| 5 | Starts or funds a program | creates, funds, renews or expands a program, grant, pilot, research effort or system | the program and its money (amounts, years), who runs it, who can apply or benefit |
| 6 | Orders a study or action | tells an agency to study, report, plan, review, train or write rules | which agency must do what, by when, delivered to whom |
| 7 | Changes how government works | offices, powers, structure, courts and judgeships, hiring, charters, budget process | what changes, for which office or body, what it may now do or no longer do |
| 8 | Overturns a rule | cancels a regulation or executive action; disapproval resolutions; blocked sales | the rule or action cancelled, what it required, that it would no longer have force |
| 9 | Transfers land | conveys land or property, or changes its status or use | what land, from whom to whom, on what conditions |
| 10 | Names something | buildings, places, offices, national symbols | one line: what is named what |
| 11 | States a view | honors, designates a day, congratulates, condemns or urges, with no legal effect | one line saying it changes no law, then what it says |
| 12 | Chamber business | how a chamber will debate a bill, its own rules, schedule or committee seats | what the chamber would do, for which bill |
| 13 | Broad package | several large parts of different kinds | its 3 to 4 biggest parts, each told as its own kind is told |

The "If this becomes law" part keeps its shape (`- label: sentence`), so the
parser and the three surfaces stay as built; what changes is what its lines
lead with, by kind. Groups of people (with "you") remain the way to tell kinds
1 to 3, and any line about people.

### Unrelated parts

Claude lists the version's separate subjects: parts that deal with unrelated
matters (H.R. 7008's passed version: trading rules for officials, and photo ID
for voters). Parts that serve one subject count as one. Each subject gets at
least one story line, and when there is more than one, "Does N unrelated
things" shows beside the kind's label. Different kinds across the subjects make
the bill a Broad package.

### Where a part came from (no AI)

For each subject, Claude names the bill's sections it comes from. When those
sections were not in the bill's first version, the site says so under the
story, from `BillHistory.origins/3`: "The photo ID part was added in the
version of Jul 22, 2026", linking to that version. Only the fact and its date,
never a reason.

### What a reply holds (prompt v4, not yet shipped, revised in place)

Two new parts, parsed like the others: `## Kind` (one line, a label from the
table, exactly) and `## Subjects` (one line per subject: `- subject: SEC. 2,
SEC. 3`). A reply whose kind is not in the table, or that has no subjects part,
shows no label and no "added" line; the story still shows.

### Calls made on this revision (mine)

- The kinds are prompt text, versioned with it; the code knows only the 13
  labels (for the label's styling and to reject a kind not in the table).
- One label style for all kinds (no colors per kind), so no kind looks better
  or worse than another.
- The second fresh sample read only each bill's opening (3,000 characters), so
  it checks the kinds, not the subject-splitting; H.R. 7008 was read whole.

---

## Revision 2, 2026-10-26: ranked effects and tags (supersedes "Kinds of bill")

A re-test showed one kind per bill fits only about 77% of bills cleanly, and
nearly every poor fit was a bill doing two kinds of thing. So the single kind
is dropped (owner, 2026-10-26). A trial on the 8 sample bills and H.R. 7008
confirmed the replacement below; its prompt is the starting point for v4.

### The story: biggest effects first

"If this becomes law" lists the bill's 1 to 4 biggest effects, largest first.
Size means, in order: the most money, the most people, the strongest legal
force. Each line is still `- label: sentence` (who or what the effect falls on;
at most 20 words; "you" when it falls on people a reader could be). Simple
lines lead, details follow, as before.

- Money the bill only authorizes is said to be authorized ("could be given up
  to…" or "authorizes"), never spent; only money it appropriates is spent.
- Lines cover the biggest subjects first; when a bill has more subjects than
  lines, the rest are listed in a fold (below).

### Tags

One or two tags from a fixed list, each defined in the prompt, shown beside the
bill's title wherever its story shows (bill page, home cards, search results),
in one style for all: Sets rules, Changes benefits, Changes taxes, Spends or
authorizes money, Creates or changes a program, Directs an agency, Changes how
government works, Cancels a rule or law, Transfers land, Names or honors,
States a view, Amends the Constitution, Chamber business. A tag not in the list
is not shown.

### Unrelated subjects

`## Subjects` lists the version's unrelated subjects, each with the sections it
comes from. Unrelated means the parts would make sense as separate bills;
parts that serve one program or purpose are one subject. With more than one,
"Does N unrelated things" shows beside the tags, and a fold "All N subjects"
lists them. The "added in" line (Revision 1, "Where a part came from") applies
to each subject.

### Each story is checked before it is shown

A second Claude call (Sonnet, prompt `priv/prompts/bill_check.v1.md`,
published) gets the bill's text (or, for a bill split into parts, the parts'
summaries) and the story's lines. It returns the lines corrected where the text
says otherwise and drops any line the text does not support. Only checked lines
are stored and shown. The written summary is cached before the check, so a
check that cannot run (budget spent, an error) is retried later without paying
for the summary again. Both calls count against the daily budget; a bill
summary now costs about 6 to 8 cents.
