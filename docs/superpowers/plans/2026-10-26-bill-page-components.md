# Bill page split into components — Plan

**Goal:** `bill_live.ex` (835 lines) keeps only state: mount, params, messages, events and the loading of summaries and history. What the page shows moves to function components, one per section of the page.

**Why (backlog item 9):** every change to the bill page means reading the whole file; the render function alone is about 400 lines, and the helpers it uses (`rep_note`, `step_when`, `option_label`, `version_label`, ...) sit between the state code.

## Global Constraints

- No visible change: same markup, same ids, `aria-label`s and order classes. The existing LiveView tests (`bill_live_test.exs`, `bill_history_live_test.exs`) pass unchanged; they are the safety net.
- No federal words in `lib/**/*.ex` outside the adapter (`boundary_test.exs`).
- `mix precommit` and `mix credo --strict` clean before each commit.

## Files

- **`lib/everyday_citizen_web/components/bill_page_components.ex`** (new), `EverydayCitizenWeb.BillPageComponents`, one public function component per section, each with its `attr`s declared:
  - `bill_header/1`: identifier, title, sponsor, follow button (render lines ~446–497)
  - `where_it_stands/1`: the status steps (~530–599), with `step_when/1`
  - `reps_on_bill/1`: the visitor's reps (~600–618), with `rep_note/1`, `person_link/1`
  - `bill_votes/1`: roll calls and positions (~619–670), with `vote_date/1`, `option_label/1`
  - `official_summary/1`: the folded official summary (~688–715)
- **`lib/everyday_citizen_web/components/bill_text_components.ex`** (new), `EverydayCitizenWeb.BillTextComponents`: the text of the bill (~716–end), with the version picker, contents, `blocks/1`, `section_summary/1`, `contents_label/1`, `version_label/1`. It is the largest part and changes on its own (section summaries, history).
- **`bill_live.ex`**: keeps mount, `handle_params`, `handle_info`, `handle_event`, the loaders (`load_history`, `assign_origins`, `load_*_summary`, `summaries_for`, ...) and a `render/1` of about 80 lines that lays out the sections. `bill_summary_source/3` and `added_parts/1` stay here or move with the AI story section, whichever needs fewer assigns passed down.
- Target: `bill_live.ex` under 350 lines; each component file under 400.

## Decisions

- Components take the assigns they show (`page`, `reps`, `version`, ...), not the whole socket's assigns, so each one's `attr`s say what it needs.
- Shared date helpers stay where they are (`FloorComponents.short_date/1`).
- No new tests: this changes no behaviour, and render-level coverage already exists. If a component loses coverage in the move (checked by deleting it temporarily and seeing a test fail), a `render_component` test is added for it.

## Steps

1. Move the bill text section to `BillTextComponents`; run the suite; commit.
2. Move the other sections to `BillPageComponents`, one commit each; suite green after each.
3. Remove now-unused helpers and aliases from `bill_live.ex`; update its moduledoc.
4. A fresh reviewer compares the rendered HTML of a bill page before and after (the same fixture bill, signed in and out, with and without a district), then merge and check a bill page in production.
