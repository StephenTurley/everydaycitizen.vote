# Bill Page Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bill text readable: keep the structure of law that a bill quotes (inserts) instead of flattening it into one paragraph, re-split every stored version, and give the bill page a three-column desktop layout.

**Architecture:** The section splitter emits quoted language as a `"quote"` block holding its own blocks; a `sections_version` column records which splitter format a version was split with, so the existing `bill_sections` on-demand job re-splits stale versions in place (pages keep showing the old split until each is redone). `BillLive` renders quotes as a labeled `<figure>`, and from `lg` (1024 px) up lays the page out as contents rail, reading column and sidebar.

**Tech Stack:** Elixir/Phoenix LiveView, Saxy.SimpleForm, Tailwind v4, Oban.

**Spec:** the approved mockups "Bill page · desktop (1024 px and up)" and "Bill text · inserted law kept in shape (phone)" in https://claude.ai/artifact/CFipwnFH7uqiZmUMf1w23J (artboards `BillDesktop.dc.html`, `BillQuoted.dc.html`), plus `docs/superpowers/specs/2026-10-23-m2-frontend-design.md` for everything they don't change.

## Global Constraints

- No UI or domain code may know it is federal; `test/the_floor/boundary_test.exs` must stay green (no congress/bioguide/senate/house/lis_member/crs under `lib/` outside `lib/the_floor/adapters/federal/`, comments included).
- The product never explains "why" in its own voice; the quote label is a plain description: **"Text this section adds to the law"**.
- Client-side JS only as LiveView hooks or `Phoenix.LiveView.JS`; no new JS dependencies.
- Phone layout (below `lg`) stays as approved in M2a apart from the quote rendering.
- Reading text: serif `"Source Serif 4", Georgia, serif` (Google Fonts, loaded beside Public Sans), 16px/1.6 on phones, 17px/1.65 from `lg`; reading column max 720px; page container max 1280px with 40px side padding from `lg`; contents rail 220px; sidebar 280–340px.
- Run `mix precommit` and `mix credo --strict` before each commit; record decisions in `docs/DECISIONS.md` (append only).

## Review Focus

1. A quote inside a subsection or paragraph (not only directly in a section) must render inside that level, indented to it, in document order relative to sibling levels.
2. Text after a quoted block (`<after-quoted-block>`) that is more than punctuation (e.g. "; and") must not be lost or glued onto the next level's text; a lone closing period may be dropped.
3. Versions split before this change must keep rendering (old shape: no `"quote"` key) until re-split, and a version whose XML fails to parse must not be re-tried forever.
4. `?section=all` and `?section=<garbage>` must not crash; Expand all must work before the live socket connects (it is a patch link with an href).
5. Phone layout order (status, your reps, summary, text, votes, source) must not change; the desktop sidebar must not duplicate content for screen readers (hidden variants use `hidden`/`lg:hidden`, i.e. display:none).

---

### Task 1: Splitter keeps quoted structure

**Files:**
- Modify: `lib/the_floor/adapters/federal/bill_sections.ex`
- Test: `test/the_floor/adapters/federal/bill_sections_test.exs` (replace the test "sections quoted into existing law stay inside their block, not as sections")

**Interfaces:**
- Produces: `BillSections.format() :: pos_integer()` returning `2`. Section entries unchanged except that `blocks` may contain `%{"level" => L, "quote" => [block]}`, where `L` is the level of the element that holds the quote and each inner block is `%{"level", "enum", "heading", "text"}` with levels counted from 0 inside the quote (`section` 0, `subsection` 0, `paragraph` 1 … as in `@levels`; containers such as `title`/`part` inside a quote become heading-only blocks at level 0). Quote blocks may nest (a quote inside a quote).

- [ ] **Step 1: Write the failing tests**

```elixir
test "law quoted into a section keeps its own numbers, headings and levels" do
  xml = """
  <bill><legis-body><section><enum>1.</enum><header>Amendment</header>
  <text>Section 5 is amended by adding:</text>
  <quoted-block><section><enum>6.</enum><header>New</header>
  <subsection><enum>(a)</enum><header>Rule</header><text>Inserted text.</text>
  <paragraph><enum>(1)</enum><text>First.</text></paragraph></subsection>
  </section><after-quoted-block>.</after-quoted-block></quoted-block>
  </section></legis-body></bill>
  """

  assert {:ok, [%{"kind" => "section", "blocks" => blocks}]} = BillSections.parse(xml)

  assert [
           %{"level" => 0, "text" => "Section 5 is amended by adding:"},
           %{"level" => 0, "quote" => [
             %{"level" => 0, "enum" => "6.", "heading" => "New", "text" => ""},
             %{"level" => 0, "enum" => "(a)", "heading" => "Rule", "text" => "Inserted text."},
             %{"level" => 1, "enum" => "(1)", "text" => "First."}
           ]}
         ] = blocks

  refute Enum.any?(blocks, &(&1["text"] =~ "Inserted text."))
end

test "a quote inside a paragraph sits at the paragraph's level, before its later siblings" do
  xml = """
  <bill><legis-body><section><enum>2.</enum><header>Changes</header>
  <subsection><enum>(a)</enum><text>Amendments.</text>
  <paragraph><enum>(1)</enum><text>by inserting:</text>
  <quoted-block><paragraph><enum>(4)</enum><text>New paragraph.</text></paragraph></quoted-block></paragraph>
  <paragraph><enum>(2)</enum><text>by striking.</text></paragraph></subsection>
  </section></legis-body></bill>
  """

  assert {:ok, [%{"blocks" => blocks}]} = BillSections.parse(xml)

  assert [
           %{"enum" => "(a)"},
           %{"enum" => "(1)", "level" => 1},
           %{"level" => 1, "quote" => [%{"enum" => "(4)", "level" => 1, "text" => "New paragraph."}]},
           %{"enum" => "(2)", "level" => 1}
         ] = blocks
end

test "USLM quoted content is kept the same way" do
  xml = """
  <bill xmlns="http://schemas.gpo.gov/xml/uslm"><main><section><num>1.</num><heading>Amendment</heading>
  <content>Section 5 is amended by adding:</content>
  <quotedContent><section><num>6.</num><heading>New</heading><content>Inserted text.</content></section></quotedContent>
  </section></main></bill>
  """

  assert {:ok, [%{"blocks" => [_, %{"quote" => [%{"enum" => "6.", "heading" => "New"}]}]}]} =
           BillSections.parse(xml)
end

test "words after a quote are kept; a lone closing period is dropped" do
  xml = """
  <bill><legis-body><section><enum>3.</enum><header>More</header><text>Amended by adding:</text>
  <quoted-block><paragraph><enum>(5)</enum><text>Five.</text></paragraph><after-quoted-block>; and</after-quoted-block></quoted-block>
  </section></legis-body></bill>
  """

  assert {:ok, [%{"blocks" => [_, %{"quote" => _}, %{"level" => 0, "text" => "; and"}]}]} =
           BillSections.parse(xml)
end

test "the format number marks the splitter's output shape" do
  assert BillSections.format() == 2
end
```

(Adjust the first test's inner section block if the implementation chooses to fold a quoted section's own text into its first block; the assertions on numbers, headings, levels, order and the absence of the quoted text from the outer block must hold.)

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/the_floor/adapters/federal/bill_sections_test.exs`
Expected: the five new tests FAIL (no `"quote"` key; `format/0` undefined).

- [ ] **Step 3: Implement in `bill_sections.ex`**

`@quotes ~w(quoted-block quotedContent)`; `own_text/1` and `label/2` skip quote elements and `after-quoted-block`; an `after-quoted-block` whose text is not only punctuation and spaces becomes a plain block at the quote's level right after it (a lone "." is dropped); `section/1` and `block/1` walk their children in document order, emitting a structural child's blocks or, for a quote child, `%{"level" => parent_level, "quote" => quote_blocks(el)}` (`section/1`'s parent level is 0). `quote_blocks/1` reuses `block/1` with `"section" => 0` added to the level map and containers emitted as heading-only level-0 blocks. Update the moduledoc's description of `blocks`. Add `@spec format() :: pos_integer()`.

- [ ] **Step 4: Run the file, then the suite**

Run: `mix test test/the_floor/adapters/federal/bill_sections_test.exs && mix test`
Expected: all pass (existing fixture tests `bill_dtd_sample.xml`/`uslm_sample.xml` still pass).

- [ ] **Step 5: Commit** — `feat: keep the structure of law a bill quotes`

---

### Task 2: Track the split format and re-split stale versions

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_bill_version_sections_version.exs` (`add :sections_version, :integer`, nullable, no default)
- Modify: `lib/the_floor/legislation/bill_version.ex` (field + cast), `lib/the_floor/ingest/records.ex` (`BillVersionText` gains `:sections_version`), `lib/the_floor/ingest/writer/legislation.ex:137` (write it), `lib/the_floor/legislation.ex:138-153`, `lib/the_floor/adapters/federal/jobs/sync_bill_text.ex:66`, `lib/the_floor/adapters/federal/jobs/backfill_bill_sections.ex`
- Test: the existing tests for `Legislation.versions_without_sections`/`put_sections` and `BackfillBillSections` (find with `grep -rn "versions_without_sections\|BackfillBillSections" test`), updated

**Interfaces:**
- Consumes: `BillSections.format/0`, `BillSections.sections_or_empty/1` (Task 1).
- Produces: `Legislation.versions_needing_sections(format :: pos_integer(), limit :: pos_integer()) :: [%{id: integer(), xml: String.t()}]` — versions with XML whose `sections_version` is null or differs from `format`, ascending id; `Legislation.put_sections(version_id, sections, format) :: :ok` sets both columns. `versions_without_sections/1` and `put_sections/2` are removed.

- [ ] **Step 1: Write the failing tests**
  - `versions_needing_sections/2` returns a version with sections but `sections_version` nil, and one with `sections_version` 1, and not one with `sections_version` 2 (format 2).
  - `BackfillBillSections` run with `%{"batch_size" => 1}` over two stale versions re-splits one, stores `sections_version == BillSections.format()`, and enqueues itself again; a version whose XML does not parse is stored with `[]` and the current format (so it is not retried).
  - `SyncBillText.store/5` writes `sections_version == BillSections.format()`.

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test <the touched test files>`
Expected: FAIL (`versions_needing_sections/2` undefined, `sections_version` unknown field).

- [ ] **Step 3: Implement**; migration, schema, record and writer fields; backfill uses `BillSections.format()` and a default `batch_size` of **100** (each job holds that many XML bodies in memory); update its moduledoc to say it also re-splits versions split by an older format.

- [ ] **Step 4: Run tests** — `mix test` → all pass.

- [ ] **Step 5: Commit** — `feat: re-split bill text split by an older format`

---

### Task 3: Render quoted law and the reading font

**Files:**
- Modify: `lib/the_floor_web/live/bill_live.ex:208-224` (extract the block list into a private function component `blocks/1` that renders itself recursively for quotes), `lib/the_floor_web/components/layouts/root.html.heex:12` (add `family=Source+Serif+4:opsz,wght@8..60,400;8..60,600;8..60,700` to the existing Google Fonts URL), `assets/css/app.css` `@theme` (`--font-serif: "Source Serif 4", Georgia, serif;`)
- Test: `test/the_floor_web/live/bill_live_test.exs`

**Interfaces:**
- Consumes: the block shape from Task 1. Must also render the old shape (no `"quote"` keys).

- [ ] **Step 1: Write the failing test** — with a bill version whose stored `sections` hold a section with blocks `[%{"level" => 0, "text" => "Section 5 is amended by adding:"}, %{"level" => 0, "quote" => [%{"level" => 0, "enum" => "6.", "heading" => "New", "text" => "Inserted text."}]}]`, opening that section (`?section=<index>`) renders a `figure` whose `figcaption` reads "Text this section adds to the law" and which contains "6." and "Inserted text."; the outer text renders outside the figure (`refute has_element?(view, "figure", "amended by adding")`).

- [ ] **Step 2: Run it** — `mix test test/the_floor_web/live/bill_live_test.exs` → FAIL (no figure).

- [ ] **Step 3: Implement** per the mockup `BillQuoted.dc.html`: `<figure>` shaded `bg-floor-ground`, rounded, indented by its level (16px per level on phones, 24px from `lg`), caption in Public Sans 11–12px uppercase semibold muted; inner blocks indent from the figure's edge; enum/heading bold as today. Text column: `font-serif text-[16px] leading-[1.6] lg:text-[17px] lg:leading-[1.65]`.

- [ ] **Step 4: Run tests** — `mix test` → all pass.

- [ ] **Step 5: Commit** — `feat: show quoted law as its own block in the bill text`

---

### Task 4: Desktop layout

**Files:**
- Modify: `lib/the_floor_web/components/layouts.ex:22-48` (replace the unused `wide` attr with `width`, values `:narrow` (default, today's `max-w-xl`) and `:full` (`max-w-xl lg:max-w-[1280px] lg:px-10`); the header's inner container uses `lg:max-w-[1280px] lg:px-10` when `:full`, else today's `max-w-3xl`), `lib/the_floor_web/live/bill_live.ex`, `lib/the_floor/bill_page.ex` (step `skipped` flag)
- Test: `test/the_floor_web/live/bill_live_test.exs`, `test/the_floor/bill_page_test.exs`

**Interfaces:**
- Produces: each `BillPage` step map gains `skipped: boolean()` — `true` when the step is `:done` with no date (shown as "Skipped" instead of "—", on both layouts). `BillLive`'s `open` assign becomes `nil | integer() | :all`.

- [ ] **Step 1: Write the failing tests**
  - BillPage: a bill with a passage action and no committee action has a Committee step with `state: :done, skipped: true`.
  - BillLive: `?section=all` renders the text of every section; the page has a "Collapse all" link then, and "Expand all" otherwise; `?section=nope` renders with no section open.
  - BillLive: the contents nav (`nav[aria-label="Sections"]`) has one link per section, each pointing at `?section=<i>` (keeping `version`), and the open one has `aria-current="location"`; title entries appear as non-link group labels.
  - BillLive: the page renders "Skipped" for the skipped step.

- [ ] **Step 2: Run them** — FAIL.

- [ ] **Step 3: Implement** per `BillDesktop.dc.html`:
  - Title band spans the full container; below it, from `lg`, a grid `lg:grid-cols-[220px_minmax(0,720px)_minmax(280px,340px)] lg:gap-10`: contents nav (col 1, `hidden lg:flex`, sticky `lg:top-4`), reading column (col 2: Text of the bill with version picker and Expand/Collapse all side by side, then Official summary), sidebar (col 3, sticky `lg:top-4 lg:self-start`: Where it stands, Your reps, Votes, source line).
  - Phone order stays status, reps, summary, text, votes, source. Ruling to apply: DOM order is sidebar (status, reps, votes, source) then reading column (summary, text); below `lg` the sidebar and reading-column wrappers are `contents` and the cards use `order-*` so phones show the approved order; from `lg` the wrappers are real grid items. (Screen readers on phones meet votes before the text — accepted; the sidebar is complementary content.)
  - Where it stands: today's horizontal bar below `lg` (`lg:hidden`), a vertical list from `lg` (`hidden lg:flex`): dot (filled done, ring current, dashed skipped, grey todo), label, date / "Now" / "Skipped" / "—".
  - Contents links: `href` to the patch path, `phx-click={JS.patch(path) |> JS.focus(to: "#section-#{i}")}`; each section's toggle link gets `id="section-#{i}"`. Expand/Collapse all are patch links to `?section=all` / without `section`.
  - Follow this bill (shown in the mockup) is M2b; leave it out.

- [ ] **Step 4: Run tests** — `mix test` → all pass.

- [ ] **Step 5: Visual check** — start the local server without workers, screenshot `/bills/119-hr-33?section=2` at 1440×2200 and 1024×1600 with headless Chrome, and at 390 wide via the same-origin iframe page (delete `priv/static/images/zz-frame.html` after). Expected: matches the mockups; no horizontal scroll at 390 or 1024.

- [ ] **Step 6: Commit** — `feat: three-column bill page on desktop`

---

### Task 5: Record and roll out

**Files:**
- Modify: `docs/DECISIONS.md` (append "2026-10-24 — Quoted law keeps its structure; split format versioned" and "2026-10-24 — Desktop bill page"), `CLAUDE.md` only if a fact there changes (none expected)

- [ ] **Step 1:** Append the two decisions (one paragraph each: what and why).
- [ ] **Step 2:** `mix precommit && mix credo --strict` → clean. Commit `docs: bill page readability decisions`.
- [ ] **Step 3 (after merge and deploy, with the user's go-ahead):** rescue jobs orphaned by the deploy, then `fly ssh console -C "/app/bin/the_floor rpc 'TheFloor.Release.ingest(\"bill_sections\")'"`. Expected: the job re-queues itself in batches of 100 until every version has `sections_version = 2`; check progress with a count of versions whose `sections_version` is distinct from 2.
