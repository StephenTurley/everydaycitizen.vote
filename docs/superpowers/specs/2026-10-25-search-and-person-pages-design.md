# Search and person pages: design

Date: 2026-10-25. Mockup the owner approved:
https://claude.ai/artifact/V8QwBjvAvvo35JGv3XYDmq (layout only; its data is
made up).

## Why

The owner wants to look up the bills people talk about (famous or
controversial ones such as the SAVE Act, the Laken Riley Act and the One Big
Beautiful Bill) and read their summaries. Today the only way in is through a
district's reps, the "This week" page or a direct link. They also want to look
up any representative by name or state, and to tap any person named on a bill
page to see what that person has done.

What success looks like:

* Someone types the name they heard on the news and gets that bill first.
* Someone types a phrase and finds the bills whose text contains it.
* Someone types a name or a state and gets that person's own page.
* On a bill page, every person's name is a link to their page.

## What gets built

### 1. One search box, on every page

A search box sits in the top bar of every page ("Search bills and people").
Submitting it opens a results page. A single query searches bills and people
together. Results come in the groups shown in the mockup, in this order:

1. **Bill number.** A query that is a bill's identifier goes straight to that
   bill's page, with no results page in between. Spacing, dots and case don't
   matter: "hr22", "H.R. 22" and "h.r.22" all match. If the identifier is
   ambiguous (it matches bills in more than one session), show the results
   page with those bills first.
2. **Bills with this name.** The query matches one of the bill's titles: the
   official title, a short title or a popular name, at any stage of the bill.
   Ranking: whole-name matches come first, then bills with more movement
   (became law, passed a chamber, had a roll call, reported, introduced), then
   the newest. Each result shows:
   * the identifier and the title that matched;
   * a status line;
   * the bill's plain-English summary, if one is already cached.
3. **Bills whose text mentions it.** Word search over each bill's latest text
   version. Each result shows the bill, the section the match is in when the
   text is split into sections, and a short excerpt with the matched words
   highlighted. Bills already listed in group 2 are left out of this group.
   Show 10 results, with "N more bills mention it" leading to further pages.
4. **People.** Matches on a person's name. Small typos are tolerated
   ("Jim Jordon"). A query that names a state or region, by full name or
   postal code, lists that place's current members. Senators come first,
   then House members in district order, each linking to their page.

An empty group is left out. If nothing matches, the page says so and suggests
checking the spelling, or searching for a bill number or a person's name.

### 2. Bill titles from the source

Today a bill stores one title. The federal adapter will also fetch each
bill's full list of titles (Congress.gov `/bill/{congress}/{type}/{number}/titles`)
and store them in a new `bill_titles` table: bill, title text, title kind,
provenance. Title kinds are normalized by the adapter into `official`,
`short` and `popular`. The title the bill already shows stays as it is.

* **Nightly sync:** the existing bill sync also fetches titles.
* **Backfill:** a one-off job fills titles for every stored bill, about 19,800
  requests. At the API's 5,000 requests an hour, this has to share the hourly
  budget with the nightly jobs and not starve them.

### 3. A page for each person

A new page for every person, at `/people/:id`, laid out as in the mockup:

* **Header:** photo if one exists, name, current role, chamber, district or
  state, party, and since when. Plus a Follow button: following a person
  already exists.
* **This week:** the AI week summary and the week's activity, with the same
  week navigation and filters as the rep panel on the reps page. Reuse that
  panel rather than building a second one.
* **Recent votes:** each vote's question, date, result and the person's
  position, linking to the bill or the vote record. Then "All votes".
* **Bills they sponsored**, and **bills they cosponsored** with a count, each
  with its status. Show the first few and then "All N".
* **Committees** and their role on each.

People who are no longer in office still get a page; it shows their last
role and their record.

On the reps page, each rep's name links to their page.

### 4. Every name on a bill page is a link

These names link to the person's page:

* the sponsor and cosponsors;
* every name in a roll call's position lists;
* reps named in the text history (who offered an amendment, and how they
  voted);
* anywhere else a person's name already shows.

## Constraints (the project's standing rules, applied here)

* **No UI or domain code knows it is federal.** Anything specific to one
  jurisdiction lives in the federal adapter, behind a jurisdiction-neutral
  interface. That covers the titles endpoint, how title kinds are mapped,
  the state names and postal codes used by place search, how a district is
  labelled ("Ohio's 4th district"), and which chamber's members are listed
  first. UI copy never names a legislature. `boundary_test.exs` must keep
  passing.
* **Search never starts an AI summary.** Results show a summary only if one
  is cached. Search pages are marked `noindex`. Person pages are indexed, and
  crawlers never start the week summary on them (the existing
  `EverydayCitizenWeb.Crawler` rule).
* **Addresses and ZIP codes are never stored, logged or put in a URL.**
  Someone will type their address into the search box. A query that looks
  like a street address or a ZIP code is not searched. It is not put in the
  URL, and the person is offered the existing find-your-reps lookup, which
  handles it the way it does now. Search queries are filtered out of request
  logs and never stored. Ordinary queries may appear in the results page's
  URL so results can be shared.
* **Provenance:** every title row carries a source URL, `fetched_at` and a
  content hash, like every other record.
* **Disk headroom:** the production database has 3 GB, with about 2.0 GB
  free, and goes read-only near full. The text index covers about 250 MB of
  bill text. Measure the index size on the local copy before migrating
  production, and keep the total under 500 MB. Prefer an index on an
  expression over a stored column that duplicates the text.
* **Tests never call outside services.** Use the Req.Test plugs
  (`no_network_test.exs`).
* **Phones first:** every new page works at phone width (see the mockup).

## Out of scope

* Bills from before the current Congress (2025 onward is what is stored).
* State legislators (that work is on hold).
* Filters (by status, date, party or sponsor), saved searches, and search
  alerts.
* Suggestions while typing. A later version could add them.
* Any notion of "famous" or "controversial" that the site decides for
  itself. Ranking uses only name match, recorded movement and date.

## Calls I made (the owner can overrule)

* One search box for both bills and people, rather than two.
* Only the latest text version of each bill is searched.
* The person page is at `/people/:id`, and reuses the reps-page rep panel.
* Search pages are `noindex`, and person pages are indexed.
* Address-like queries go to the existing reps lookup instead of being
  searched.
* Name searches tolerate typos, and text search does not.

## Left to the builder

* The Postgres search setup: text search configuration, `pg_trgm` for names,
  and whether to index with GIN or GiST.
* How to make the excerpt (`ts_headline` limited to the results shown, or
  something cheaper).
* How the top-bar form sends its query from any LiveView.
* Page sizes, and how many items each person-page section shows before "All".
* The exact rule for spotting an address- or ZIP-shaped query, provided it
  errs toward treating a query as an address.

## Details settled before planning (my calls, from the builder check)

* **Which text is searched.** Each bill's latest version that has text: the
  highest-dated `bill_versions` row with `plain_text`. Index `plain_text`
  with an expression GIN index over all versions, and pick the latest version
  when querying. That avoids an index that has to be maintained as versions
  arrive. The section for an excerpt is found afterwards, only for the
  results shown, by locating the match in that version's `sections`. When
  that fails, show the excerpt without a section label.
* **What the 500 MB covers.** Everything this work adds to the database: the
  text index, `bill_titles`, and the trigram indexes on titles and names.
* **Titles before the backfill finishes.** Ship without waiting. Name search
  also covers the existing `bills.title`, so it works from day one and gets
  better as titles arrive. The backfill runs below the nightly jobs: it may
  take a day or more, and it uses only the request budget left over. Build
  this on the existing rate limiter, and add a priority or a per-hour cap
  only if the limiter can't express it.
* **Name-match ranking**, as a strict order:
  1. A whole-name match: the title equals the query, ignoring case,
     punctuation, and a trailing "Act" or "of <year>".
  2. A title containing the query as a phrase.
  3. A title containing all the query's words.

  Within each tier, sort by the furthest stage reached (became law, passed
  a chamber, had a roll call, reported, introduced), then newest first.
* **Person URL.** `/people/:id` uses the internal id. The database is never
  rebuilt (`ecto.reset` and `ecto.drop` are banned), so the id is stable.
  The page shows no external ids.
* **Former members.** Their page opens on the most recent week they had
  activity. Their week summary follows the same rules as everyone else's:
  written on view, cached, inside the daily budget, and never started by a
  crawler. If the rep panel is tied to its district, extract it into a
  shared component that both pages use.
* **Votes with no bill** (nominations and procedural votes) are listed too.
  They link to what the vote record already links: the subject's official
  page, or the vote's source. "All votes" and "All N" bills expand in place,
  page by page. There are no new routes.
* **How the top bar sends a query.** It sends a LiveView event, attached to
  every LiveView through an `on_mount` hook. The server classifies the
  query:
  * an ordinary query navigates to `/search?q=…`;
  * an address- or ZIP-shaped query goes to the find-your-reps form, with
    nothing in the URL.

  `q` is added to Phoenix's filtered parameters, and to Sentry scrubbing,
  so even a hand-typed URL isn't logged.
* **A query that matches both a place and a name** ("Washington") shows both
  groups: the place's members, then people by name. A bare number like "22"
  is treated as a bill number in every bill type ("H.R. 22", "S. 22"), shown
  as results rather than jumping to one bill. Territories and delegates
  count as places when the adapter's data includes them.
* **Where the code goes.** A new jurisdiction-neutral `EverydayCitizen.Search`
  context. Place names, postal codes, district labels and the chamber order
  come from a callback the adapter implements. Follow the pattern the
  geocoder or locator already uses for adapter callbacks.
* **Very broad queries.** A query under 2 characters, or one made only of
  common words, returns a "try more specific words" message. Text search is
  capped in SQL: it ranks at most the first 1,000 matches.
