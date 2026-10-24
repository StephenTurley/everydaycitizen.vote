# M2 front end: your reps, bill pages, follow and alerts, this week

Date: 2026-10-23. Status: draft for review. Mockups (phone):
https://claude.ai/artifact/CFipwnFH7uqiZmUMf1w23J (boards "A · One rep at a time" and
"Bill page (M2)"; board B was the rejected alternative).

## Intent

A constituent comes to see what their own representatives (their House member and
both senators) have been doing: how they voted, what they introduced, and what they
actually got changed. Everything shown is the record, linked to its official source;
the product never characterizes motives in its own voice (spec §3, CLAUDE.md). M2 is
the milestone where the product ships (spec §8): a user can find their reps and
follow a bill end to end.

## Goals

1. Find your reps from an address (spec §7.2), then land on the rep page.
2. Rep page: one rep at a time, with their activity as a single feed.
3. Bill page: where it stands, your reps' involvement, the official summary, the text.
4. Accounts: sign in by emailed link or passkey; follow bills and reps.
5. A daily email, only on days something followed changed.
6. "This week": what is scheduled on the floor and in committee, filterable to your
   reps and followed bills.

## Non-goals for M2 (planned later, keep room for them)

- Plain-language summaries of bill sections (M3), and an M3 summary at the top of a
  rep page of what they have been up to. Same rules as M3: generated, clause-anchored,
  labeled as machine-written, two configurations with disagreement flagged, prompts
  published, "report an inaccuracy". The rep summary describes what they did, never why.
- Redline against current law (M4).
- Tracked changes between bill versions with attribution (floor amendments by sponsor;
  House committee amendments from docs.house.gov; otherwise "changed in committee").
- The why-panel (M5), extended: lobbying disclosures that name the bill, FEC campaign
  finance, the sponsor's and opponents' own words (Congressional Record speeches,
  committee reports, press releases), CBO costs, and news coverage labeled by outlet
  from a published outlet list with several sides shown together.
- Push notifications; any debate, proposal or delivery feature (spec §9).

## Anti-goals (a failure even if it works)

- The product's own verdict on motives ("corruption", "odd", "campaign promise").
  It shows labeled facts side by side; readers conclude.
- Any summary shown without the text it came from; any claim without a link to the
  official record.
- Party colors (red/blue) or anything else that reads as partisan styling.
- Storing a street address (spec §7.2).

## Constraints

- Phoenix LiveView only; client JS limited to LiveView hooks (CLAUDE.md). Passkeys
  need the WebAuthn browser API, which goes in a hook.
- No UI or domain code may know it is federal: pages say "chamber", "session",
  "roll call" from the data, never hard-coded "Senate"/"Congress" logic. Federal
  wording comes from stored bodies, sessions and identifiers. `boundary_test.exs`
  enforces the vocabulary ban under `lib/` outside the adapter.
- Phone first: every screen is designed at 390 px wide and must also work on desktop.
- Accessibility: real links/buttons/labels, 44 px touch targets, text contrast ≥ 4.5:1;
  Yea/Nay/absent differ by fill and label, never by color alone.
- Data sources as in M1; Senate votes come from Voteview and are labeled so.

## Screens (as decided)

### Look
Neutral and civic: Public Sans, a gray ground (#F4F5F6), white cards, near-black ink
(#15171A), one accent (deep teal #0B5563). Vote positions: "Yea" solid dark chip,
"Nay" outlined chip, "Not voting"/"No vote yet" gray chip. Each page ends with a
plain line naming its sources and a link to the official record.

### Find your reps
Address in, district out (Census Geocoder, spec §5). The address is used once and
discarded; only the district is kept (on the account when signed in).

### Rep page (mockup board A)
- A row of the three reps at the top (photo-less initials, name, role, party letter);
  one is selected; switching shows that rep.
- Rep header: name, party, state/district, current congress; counts of bills introduced
  and cosponsored.
- Filters: Everything, Votes, Their bills, Became law.
- A feed, newest first, grouped by day. Item kinds: a roll-call vote ("Voted Yea/Nay",
  question, result and tally, roll-call number, the bill); a bill they introduced
  (with its latest action); their bill moved (passed a chamber, reported, etc.);
  their bill became law. Bill items for moving bills carry a "What it would change"
  box with the CRS summary now and a link to the redline later.
- Every item links to its bill page.

### Bill page (mockup board "Bill page (M2)")
Top to bottom:
1. Back link, bill number and congress, short title, long title, sponsor and
   cosponsor count, "Follow bill".
2. Where it stands: a five-step status line (Introduced, Committee, first chamber,
   second chamber, Law) with dates, the current step marked, a one-sentence account
   of the latest action, and a link to all actions.
3. Your reps on this bill: each of your three reps with their position on the main
   vote, sponsorship, or "no vote yet".
4. Official summary: the CRS summary, labeled as written by the Congressional Research
   Service.
5. Text of the bill: a version picker (each stored version with its date), then the
   sections as an expandable list; an open section shows its text with its structure
   (subsections indented) and, reserved for M3, the plain-language summary slot above
   it.
6. Votes on this bill (roll calls with result and tally), then the official-record link.

### Accounts
- Sign up and sign in by emailed link (Phoenix 1.8 `phx.gen.auth`, magic-link flow).
- After signing in, add one or more passkeys and sign in with them; built the way
  turley.dev does it (`wax_` library, LiveView hook for the WebAuthn calls).
- The account holds: email, district, followed bills and reps.

### Follow and the daily email
- Follow a bill (bill page) or a rep (rep page). Following requires an account.
- One email per day, only if something followed changed that day:
  - a followed bill: a new action, a new text version, a roll-call vote on it;
  - a followed rep: the same item kinds as their feed.
- Each item links to its page; one-click unsubscribe in every email.
- Sent with Swoosh through Resend (as turley.dev). Needs the owner's Resend account,
  `thefloor.vote` verified with Resend's DNS records at Namecheap, and the API key as a
  Fly secret documented in `.env.example`. Until then, dev uses the local mailbox.

### This week
What is scheduled in the coming seven days: floor items and committee meetings
(hearings, markups) from the stored events, each with its date, body and linked bills,
filterable to "my reps" (bills they sponsor or committees they sit on) and "followed
bills". It answers "what is about to happen"; the "why" lives on bill pages (later).

## Data work M2 depends on

- CRS summaries: not stored yet. They are in the BILLSTATUS bulk files already fetched
  (and the API's summaries endpoint); store the latest per version. The bulk parser
  currently collapses repeated non-`item` elements such as `<summaries><summary>` to the
  last one, which must be fixed first.
- Action classifier: "Motion to proceed … agreed to … by Yea-Nay Vote" is classified
  `passed_chamber` (seen on S. 4668, Sep 17), which would mark a bill passed early. The
  status line depends on correct `passed_chamber`.
- House votes: in production after the backfill; the dev database lacks them.
- Main vote per bill (for "Your reps on this bill"): passage if there is one, else the
  latest roll call on the bill.

## Settled after review

Answered by the project's rules, or settled by the designer (marked "designer's call");
none of these was asked of the owner.

1. **Finding reps (rule).** The Census Geocoder is federal, so it lives in the federal
   adapter behind a generic behaviour: `locate(address) -> {:ok, [{body_external_id,
   district | nil}]}`, which domain code turns into current memberships. "Your reps" =
   every current member of the returned bodies for that district (statewide seats have
   no district). Designer's call: at-large members and non-voting delegates are shown
   like any member, labeled as the data names them; places with no senators show none.
2. **Main vote and positions (designer's call).** The adapter normalizes each vote into
   a `classification` (passage, cloture, amendment, procedural, nomination, other) when
   it writes votes; that is a schema change plus a backfill of existing votes. The
   "your reps" panel shows each rep their own chamber's main vote: passage there if any,
   else that chamber's latest roll call on the bill, else "no vote yet". A rep who was
   not a member at the time shows "not in office".
3. **Rep feed (designer's call).** A query over votes, sponsorships and bill actions
   unioned in the domain, no feed table; paginate by (date, kind, id). "Their bills"
   means bills they sponsored. Cosponsored bills are counted in the header and are
   their own filter later, not in the feed. "Their bill moved" items are only actions
   in the movement filter (reported, scheduled, passed_chamber, enrolled, signed,
   became_law), never every action.
4. **Accounts (owner, restated).** No passwords: emailed link plus passkeys. Finding
   reps, rep pages, bill pages and "this week" all work without an account; only
   following needs one. A signed-in user's saved district is used until they enter a
   new address, which replaces it.
5. **Passkeys (reference).** The reference is turley.dev at `~/Projects/turley.dev`:
   `lib/turley_dev/accounts/passkeys.ex`, `user_key.ex`, `cose_key.ex`, its WebAuthn
   config (`config :turley_dev, :webauthn` with origin, rp_id, rp_name per environment)
   and its LiveView hook in `assets/js`. Read it and follow it. For The Floor: rp_id
   `thefloor.vote`, origin `https://thefloor.vote` in production (the canonical-host
   redirect ensures that), `localhost` in dev.
6. **Daily email (designer's call).** "Changed" means a row first stored (its
   `inserted_at`) since the user's last sent digest, not a re-fetch of an unchanged
   record. Items are shown with their own event dates. Day = America/New_York, sent
   at 7:00. A missed day catches up: the next digest covers everything since the last
   one sent. One digest per user per day (unique job).
7. **CRS summaries (designer's call).** A new `bill_summaries` table: bill, version code
   (or action description when no version), action date, text, source (provenance as
   every record). The summary HTML is sanitized to a small allow-list (paragraphs,
   lists, emphasis) and stored as such. Fixing the bulk parser's repeated-element
   collapse and storing summaries are the first tasks of the M2 plan, not a separate PR.
8. **Data to build against (designer's call).** Tests use fixtures. Dev uses real
   ingest; run `mix the_floor.ingest house_votes` locally to get House votes.
9. **"This week" filters (designer's call).** "My reps" covers bills they sponsored or
   cosponsored and meetings of committees they sit on. Events whose bill labels did not
   resolve are still listed, without a bill link.
10. **Bill sections (fact plus designer's call).** Versions store the source XML (the
    older bill format for the 119th Congress, not USLM; DECISIONS R15) plus flattened
    plain text; sections are not stored as structure. Parse sections and their
    hierarchy from the stored XML (section, subsection, paragraph and so on), once
    when text is stored, into a structure the page renders. The same structure is where
    M3 attaches summaries per section.

## Left to the builder

- Page structure in LiveView, components, routes, URL scheme.
- How a visitor without an account keeps their district between visits (cookie or
  none), within the rule that no address is stored.
- Feed queries and pagination; what counts as the "latest action" sentence.
- Exact email layout and send time; the digest job (Oban) and its idempotency.
- Rep photos (none in the mockups; initials are fine).
- How the "this week" filter decides "my reps" beyond sponsorship and committee seats.
- Desktop layout (the phone layout widened is acceptable).
