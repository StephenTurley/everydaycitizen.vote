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
      case Integer.parse(params["section"] || "") do
        {n, ""} -> n
        _ -> nil
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="-mx-5 px-5 pt-4 pb-5 bg-floor-card border-b border-floor-line flex flex-col gap-2.5">
        <.link
          :if={@district}
          navigate={~p"/reps/#{@district}"}
          class="text-[14px] font-medium text-floor-accent py-1"
        >
          ‹ Back to your reps
        </.link>
        <.eyebrow>{@page.bill.identifier}</.eyebrow>
        <h1 class="m-0 text-[26px] leading-tight font-bold tracking-tight">{@page.bill.title}</h1>
        <p :if={@page.sponsor} class="m-0 text-[14px] text-floor-muted">
          Sponsor: {@page.sponsor.name} · {cosponsors(@page.cosponsor_count)}
        </p>
      </section>

      <section aria-label="Where it stands" class="py-5 flex flex-col gap-3.5">
        <h2 class="m-0 text-[18px] font-bold">Where it stands</h2>
        <ol
          class="m-0 p-0 list-none grid gap-1"
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
            <span class="text-[12px] text-floor-muted">
              {cond do
                step.state == :current -> "Now"
                step.date -> date(step.date)
                true -> "—"
              end}
            </span>
          </li>
        </ol>
        <p :if={@page.latest_action} class="m-0 text-[15px] leading-relaxed">
          {@page.latest_action.description}{if @page.latest_action.date,
            do: " (#{date(@page.latest_action.date)})"}
        </p>
      </section>

      <section :if={@page.reps != []} aria-label="Your reps on this bill" class="pb-5">
        <.card class="flex flex-col gap-3">
          <h2 class="m-0 text-[18px] font-bold">Your reps on this bill</h2>
          <div :for={rep <- @page.reps} class="flex items-center justify-between gap-2">
            <div class="flex flex-col gap-0.5">
              <span class="text-[15px] font-semibold">{rep.person.name}</span>
              <span :if={note = rep_note(rep)} class="text-[13px] text-floor-muted">{note}</span>
            </div>
            <.vote_chip option={rep.state} />
          </div>
        </.card>
      </section>

      <section aria-label="Official summary" class="pb-5 flex flex-col gap-2.5">
        <h2 class="m-0 text-[18px] font-bold">Official summary</h2>
        <p :if={!@page.summary} class="m-0 text-[15px] text-floor-muted">No official summary yet.</p>
        <%= if @page.summary do %>
          <p class="m-0 text-[13px] text-floor-muted">Written by the {@page.summary.author}.</p>
          <.card class="text-[15px] leading-relaxed text-floor-ink-2 [&_p]:m-0 [&_p+p]:mt-2 [&_ul]:list-disc [&_ul]:pl-5">
            {Phoenix.HTML.raw(@page.summary.html)}
          </.card>
        <% end %>
      </section>

      <section aria-label="Text of the bill" class="pb-5 flex flex-col gap-3">
        <h2 class="m-0 text-[18px] font-bold">Text of the bill</h2>
        <p :if={@page.versions == []} class="m-0 text-[15px] text-floor-muted">
          No text published yet.
        </p>
        <form
          :if={@page.versions != []}
          id="version-form"
          phx-change="version"
          class="flex flex-col gap-1.5"
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
              class="m-0 px-4 pt-4 pb-1 text-[12px] font-semibold uppercase tracking-wide text-floor-muted"
            >
              {entry["enum"]} {entry["heading"]}
            </p>
            <div :if={entry["kind"] == "section"} class="border-b border-floor-line-soft">
              <.link
                patch={
                  section_path(
                    @page.bill,
                    @version,
                    if(@open == i, do: nil, else: i)
                  )
                }
                class="flex justify-between items-center gap-2 px-4 py-3.5 text-floor-ink"
                aria-expanded={to_string(@open == i)}
              >
                <span class="text-[15px]">
                  <strong :if={entry["enum"]} class="font-semibold">Sec. {entry["enum"]}</strong>
                  {entry["heading"]}
                </span>
                <span aria-hidden="true" class="text-floor-muted">{toggle(@open == i)}</span>
              </.link>
              <%!-- M3 puts each section's plain-language summary above its text --%>
              <div
                :if={@open == i}
                class="section-text px-4 pb-4 font-serif text-[15px] leading-relaxed flex flex-col gap-2"
              >
                <p
                  :for={block <- entry["blocks"]}
                  data-level={block["level"]}
                  class="m-0"
                  style={"padding-left: #{block["level"] * 16}px"}
                >
                  <strong :if={block["enum"] || block["heading"]}>
                    {block["enum"]} {block["heading"]}{if block["heading"], do: "."}
                  </strong>
                  {block["text"]}
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <section aria-label="Votes on this bill" class="pb-5 flex flex-col gap-2.5">
        <h2 class="m-0 text-[18px] font-bold">Votes</h2>
        <p :if={@page.votes == []} class="m-0 text-[15px] text-floor-muted">
          No roll-call votes yet.
        </p>
        <.card :for={vote <- @page.votes} class="!p-3.5 flex flex-col gap-0.5">
          <span class="text-[15px] font-semibold">{vote.question} · {vote.result}, {vote.yea_count}–{vote.nay_count}</span>
          <span class="text-[13px] text-floor-muted">{vote.body.name} · {vote.identifier} · {vote_date(
            vote
          )}</span>
        </.card>
      </section>

      <footer class="pb-4 flex flex-col gap-2">
        <a href={@page.bill.source.url} class="text-[14px] font-semibold text-floor-accent py-1">Source record</a>
        <.source_line>Every item on this page comes from the official record.</.source_line>
      </footer>
    </Layouts.app>
    """
  end
end
