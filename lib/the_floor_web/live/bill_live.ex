defmodule TheFloorWeb.BillLive do
  @moduledoc """
  The bill page (mockup "Bill page (M2)"): the bill and its sponsor, where it
  stands, the visitor's reps' part in it, the official summary labeled with its
  author, the text by section with a version picker, and its roll calls.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.{BillPage, Reps}

  @impl true
  def mount(%{"id" => id}, session, socket) do
    district = session["district"]
    reps = if district, do: Reps.for_district(district), else: []

    case BillPage.load(Reps.jurisdiction(), id, reps) do
      {:ok, page} ->
        {:ok, assign(socket, page: page, district: district, page_title: page.bill.identifier)}

      :not_found ->
        raise TheFloorWeb.NotFoundError
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    versions = socket.assigns.page.versions
    version = Enum.find(versions, &(&1.code == params["version"])) || List.first(versions)

    open =
      case params["section"] do
        "all" ->
          :all

        section ->
          case Integer.parse(section || "") do
            {n, ""} -> n
            _ -> nil
          end
      end

    sections = BillPage.sections(socket.assigns.page.bill, version && version.code)
    {:noreply, assign(socket, version: version, sections: Enum.with_index(sections), open: open)}
  end

  @impl true
  def handle_event("version", %{"version" => code}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/bills/#{socket.assigns.page.bill.external_id}?#{[version: code]}")}
  end

  defp section_path(bill, version, enum) do
    ~p"/bills/#{bill.external_id}?#{Enum.reject([version: version && version.code, section: enum], &is_nil(elem(&1, 1)))}"
  end

  defp open?(open, i), do: open == :all or open == i

  defp contents_label(%{"enum" => enum, "heading" => heading}),
    do:
      [enum && String.trim_trailing(enum, "."), heading]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

  defp step_when(%{state: :current}), do: "Now"
  defp step_when(%{skipped: true}), do: "Skipped"
  defp step_when(%{date: %Date{} = d}), do: date(d)
  defp step_when(_step), do: "—"

  defp toggle(true), do: "−"
  defp toggle(false), do: "+"

  defp date(d), do: Calendar.strftime(d, "%b %-d")

  defp vote_date(vote),
    do: vote.voted_at |> DateTime.shift_zone!("America/New_York") |> DateTime.to_date() |> date()

  defp cosponsors(1), do: "1 cosponsor"
  defp cosponsors(n), do: "#{n} cosponsors"

  defp version_label(v), do: "#{v.classification || v.code}#{if v.date, do: " · #{date(v.date)}"}"

  defp rep_note(%{state: :sponsor}), do: "Sponsor of this bill"
  defp rep_note(%{state: :cosponsor}), do: "Cosponsor of this bill"
  defp rep_note(%{state: :no_vote, body: body}), do: "The #{body.name} hasn't voted"
  defp rep_note(%{vote: vote}) when not is_nil(vote), do: "#{vote.question}, #{vote_date(vote)}"
  defp rep_note(_), do: nil

  attr :blocks, :list, required: true

  # A section's text by level; law the bill quotes is set off as its own block.
  defp blocks(assigns) do
    ~H"""
    <%= for block <- @blocks do %>
      <figure
        :if={block["quote"]}
        class="m-0 ml-[calc(var(--level)*16px)] lg:ml-[calc(var(--level)*24px)] px-3 py-3 lg:px-5 lg:py-4 rounded-[10px] bg-floor-ground flex flex-col gap-2"
        style={"--level: #{block["level"]}"}
      >
        <figcaption class="font-sans text-[11px] lg:text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
          Text this section adds to the law
        </figcaption>
        <.blocks blocks={block["quote"]} />
      </figure>
      <p
        :if={!block["quote"]}
        data-level={block["level"]}
        class="m-0 pl-[calc(var(--level)*16px)] lg:pl-[calc(var(--level)*24px)]"
        style={"--level: #{block["level"]}"}
      >
        <strong :if={block["enum"] || block["heading"]}>
          {block["enum"]} {block["heading"]}{if block["heading"] && block["text"] not in [nil, ""],
            do: "."}
        </strong>
        {block["text"]}
      </p>
    <% end %>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width={:full}>
      <%!-- From lg the band's white runs edge to edge (the ::before), past the
           1280px column --%>
      <section class="relative z-0 -mx-5 px-5 lg:-mx-10 lg:px-10 pt-4 pb-5 lg:pt-5 lg:pb-7 bg-floor-card border-b border-floor-line lg:bg-transparent lg:border-b-0 lg:before:absolute lg:before:inset-y-0 lg:before:left-1/2 lg:before:w-screen lg:before:-translate-x-1/2 lg:before:-z-10 lg:before:bg-floor-card lg:before:border-b lg:before:border-floor-line flex flex-col gap-2.5">
        <.link
          :if={@district}
          navigate={~p"/reps/#{@district}"}
          class="self-start text-[14px] font-medium text-floor-accent py-1"
        >
          ‹ Back to your reps
        </.link>
        <.eyebrow>{@page.bill.identifier}</.eyebrow>
        <h1 class="m-0 text-[26px] lg:text-[34px] lg:max-w-[920px] leading-tight font-bold tracking-tight">
          {@page.bill.title}
        </h1>
        <p :if={@page.sponsor} class="m-0 text-[14px] lg:text-[15px] text-floor-muted">
          Sponsor: {@page.sponsor.name} · {cosponsors(@page.cosponsor_count)}
        </p>
      </section>

      <%!-- Phones: one column in the order below (`order-*`; the two wrappers are
           `contents`). lg: text and summary | sidebar. xl: contents | text | sidebar. --%>
      <div class="flex flex-col lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(280px,320px)] xl:grid-cols-[220px_minmax(0,720px)_minmax(280px,340px)] lg:gap-10 lg:pt-7 lg:items-start">
        <nav
          :if={@sections != []}
          aria-label="Sections"
          class="hidden xl:flex xl:col-start-1 xl:row-start-1 flex-col gap-0.5 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto"
        >
          <p class="m-0 mb-2 text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
            Contents
          </p>
          <%= for {entry, i} <- @sections do %>
            <p
              :if={entry["kind"] == "title"}
              class="m-0 mt-3 mb-0.5 text-[13px] font-semibold text-floor-ink-2"
            >
              {contents_label(entry)}
            </p>
            <.link
              :if={entry["kind"] == "section"}
              patch={section_path(@page.bill, @version, i)}
              phx-click={JS.focus(to: "#section-#{i}")}
              aria-current={if @open == i, do: "location"}
              class={[
                "px-2.5 py-1.5 rounded-lg text-[14px] leading-snug",
                if(@open == i,
                  do: "bg-floor-line-soft font-semibold text-floor-ink",
                  else: "text-floor-ink-2 hover:bg-floor-line-soft"
                )
              ]}
            >
              {contents_label(entry)}
            </.link>
          <% end %>
        </nav>

        <aside class="contents lg:flex lg:flex-col lg:gap-4 lg:col-start-2 xl:col-start-3 lg:row-start-1 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
          <section
            aria-label="Where it stands"
            class="order-1 py-5 lg:p-[18px] lg:bg-floor-card lg:border lg:border-floor-line lg:rounded-xl flex flex-col gap-3.5 lg:gap-3"
          >
            <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Where it stands</h2>
            <ol
              class="m-0 p-0 list-none grid gap-1 lg:hidden"
              style={"grid-template-columns: repeat(#{length(@page.steps)}, minmax(0, 1fr))"}
            >
              <li
                :for={step <- @page.steps}
                aria-current={if step.state == :current, do: "step"}
                class="flex flex-col gap-1.5"
              >
                <span class={[
                  "h-1.5 rounded-sm",
                  step.state == :done && "bg-floor-accent",
                  step.state == :current && "bg-floor-card border-2 border-floor-accent box-border",
                  step.state == :todo && "bg-floor-line"
                ]} />
                <span class={[
                  "text-[12px] leading-tight [overflow-wrap:anywhere] hyphens-auto",
                  if(step.state == :todo, do: "font-semibold text-floor-muted", else: "font-semibold")
                ]}>
                  {step.label}
                </span>
                <span class="text-[12px] text-floor-muted">{step_when(step)}</span>
              </li>
            </ol>
            <ol class="hidden lg:flex m-0 p-0 list-none flex-col gap-2.5">
              <li
                :for={step <- @page.steps}
                aria-current={if step.state == :current, do: "step"}
                class="flex items-center gap-2.5"
              >
                <span
                  aria-hidden="true"
                  class={[
                    "size-3 rounded-full flex-none box-border",
                    step.state == :done && !step.skipped && "bg-floor-accent",
                    step.skipped && "bg-floor-card border-2 border-dashed border-[#8a9099]",
                    step.state == :current && "bg-floor-card border-[3px] border-floor-accent",
                    step.state == :todo && "bg-floor-line"
                  ]}
                />
                <span class={[
                  "flex-1 text-[14px]",
                  step.state == :current && "font-bold",
                  step.state == :todo && "font-semibold text-floor-muted",
                  step.state == :done && "font-semibold"
                ]}>
                  {step.label}
                </span>
                <span class={[
                  "text-[13px]",
                  if(step.state == :current,
                    do: "font-semibold text-floor-ink",
                    else: "text-floor-muted"
                  )
                ]}>
                  {step_when(step)}
                </span>
              </li>
            </ol>
            <p :if={@page.latest_action} class="m-0 text-[15px] lg:text-[14px] leading-relaxed">
              {@page.latest_action.description}{if @page.latest_action.date,
                do: " (#{date(@page.latest_action.date)})"}
            </p>
          </section>

          <section
            :if={@page.reps != []}
            aria-label="Your reps on this bill"
            class="order-2 pb-5 lg:pb-0"
          >
            <.card class="flex flex-col gap-3">
              <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Your reps on this bill</h2>
              <div :for={rep <- @page.reps} class="flex items-center justify-between gap-2">
                <div class="flex flex-col gap-0.5">
                  <span class="text-[15px] lg:text-[14px] font-semibold">{rep.person.name}</span>
                  <span :if={note = rep_note(rep)} class="text-[13px] text-floor-muted">{note}</span>
                </div>
                <.vote_chip option={rep.state} />
              </div>
            </.card>
          </section>

          <section aria-label="Votes on this bill" class="order-5 pb-5 lg:pb-0 flex flex-col gap-2.5">
            <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Votes</h2>
            <p :if={@page.votes == []} class="m-0 text-[15px] text-floor-muted">
              No roll-call votes yet.
            </p>
            <.card :for={vote <- @page.votes} class="!p-3.5 flex flex-col gap-0.5">
              <span class="text-[15px] lg:text-[14px] font-semibold">{vote.question} · {vote.result}, {vote.yea_count}–{vote.nay_count}</span>
              <span class="text-[13px] text-floor-muted">{vote.body.name} · {vote.identifier} · {vote_date(
                vote
              )}</span>
            </.card>
          </section>

          <footer class="order-6 pb-4 flex flex-col gap-2">
            <a
              href={@page.bill.source.url}
              class="self-start text-[14px] font-semibold text-floor-accent py-1"
            >Source record</a>
            <.source_line>Every item on this page comes from the official record.</.source_line>
          </footer>
        </aside>

        <div class="contents lg:flex lg:flex-col lg:gap-6 lg:col-start-1 xl:col-start-2 lg:row-start-1 lg:min-w-0">
          <section aria-label="Official summary" class="order-3 lg:order-2 pb-5 flex flex-col gap-2.5">
            <h2 class="m-0 text-[18px] lg:text-[22px] font-bold">Official summary</h2>
            <p :if={!@page.summary} class="m-0 text-[15px] text-floor-muted">
              No official summary yet.
            </p>
            <%= if @page.summary do %>
              <p class="m-0 text-[13px] text-floor-muted">Written by the {@page.summary.author}.</p>
              <.card class="text-[15px] leading-relaxed text-floor-ink-2 [&_p]:m-0 [&_p+p]:mt-2 [&_ul]:list-disc [&_ul]:pl-5">
                {Phoenix.HTML.raw(@page.summary.html)}
              </.card>
            <% end %>
          </section>

          <section
            aria-label="Text of the bill"
            class="order-4 lg:order-1 pb-5 flex flex-col gap-3 lg:gap-4"
          >
            <h2 class="m-0 text-[18px] lg:text-[22px] font-bold">Text of the bill</h2>
            <p :if={@page.versions == []} class="m-0 text-[15px] text-floor-muted">
              No text published yet.
            </p>
            <div :if={@page.versions != []} class="flex flex-wrap items-end gap-2.5">
              <form
                id="version-form"
                phx-change="version"
                class="flex-1 min-w-[200px] flex flex-col gap-1.5"
              >
                <label for="version" class="text-[13px] font-semibold text-floor-muted">Version</label>
                <select
                  id="version"
                  name="version"
                  class="text-[15px] p-3 border border-[#b8bdc4] rounded-xl bg-floor-card"
                >
                  <option
                    :for={v <- @page.versions}
                    value={v.code}
                    selected={@version && v.code == @version.code}
                  >
                    {version_label(v)}
                  </option>
                </select>
              </form>
              <.link
                :if={@sections != []}
                patch={section_path(@page.bill, @version, if(@open == :all, do: nil, else: "all"))}
                class="px-3.5 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card text-[14px] font-semibold text-floor-accent"
              >
                {if @open == :all, do: "Collapse all", else: "Expand all"}
              </.link>
            </div>
            <p :if={@version && @sections == []} class="m-0 text-[15px] text-floor-muted">
              The text of this version isn't available yet.
            </p>
            <div
              :if={@sections != []}
              class="bg-floor-card border border-floor-line rounded-xl overflow-hidden"
            >
              <%= for {entry, i} <- @sections do %>
                <p
                  :if={entry["kind"] == "title"}
                  class="m-0 px-4 lg:px-7 pt-4 pb-1 text-[12px] font-semibold uppercase tracking-wide text-floor-muted"
                >
                  {entry["enum"]} {entry["heading"]}
                </p>
                <div :if={entry["kind"] == "section"} class="border-b border-floor-line-soft">
                  <.link
                    id={"section-#{i}"}
                    patch={
                      section_path(
                        @page.bill,
                        @version,
                        if(open?(@open, i), do: nil, else: i)
                      )
                    }
                    class="flex justify-between items-center gap-2 px-4 lg:px-7 py-3.5 text-floor-ink"
                    aria-expanded={to_string(open?(@open, i))}
                  >
                    <span class="text-[15px] lg:text-[16px]">
                      <strong :if={entry["enum"]} class="font-semibold">Sec. {entry["enum"]}</strong>
                      {entry["heading"]}
                    </span>
                    <span aria-hidden="true" class="text-floor-muted">{toggle(open?(@open, i))}</span>
                  </.link>
                  <%!-- M3 puts each section's plain-language summary above its text --%>
                  <div
                    :if={open?(@open, i)}
                    class="section-text px-4 lg:px-7 pb-4 lg:pb-7 font-serif text-[16px] leading-[1.6] lg:text-[17px] lg:leading-[1.65] flex flex-col gap-2.5"
                  >
                    <.blocks blocks={entry["blocks"]} />
                  </div>
                </div>
              <% end %>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
