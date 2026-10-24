defmodule TheFloorWeb.RepsLive do
  @moduledoc """
  A district's reps, one at a time (mockup board A): the row of reps, the
  selected rep's header and counts, filters, and their activity feed grouped by
  day, each item linking to its bill page.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.{Activity, Legislation, Reps}

  @filters [
    {"all", "Everything", :all},
    {"votes", "Votes", :votes},
    {"bills", "Their bills", :bills},
    {"law", "Became law", :law}
  ]

  @impl true
  def mount(%{"district" => district}, _session, socket) do
    {:ok, assign(socket, district: district, reps: Reps.for_district(district))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    reps = socket.assigns.reps
    rep = Enum.find(reps, &(to_string(&1.person.id) == params["rep"])) || List.first(reps)
    filter = Enum.find(@filters, {"all", "Everything", :all}, &(elem(&1, 0) == params["filter"]))

    socket =
      socket
      |> assign(rep: rep, filter: filter, page_title: rep && rep.person.name)
      |> assign(counts: rep && Activity.counts(rep.person.id))
      |> load_feed(nil, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("more", _params, socket) do
    {:noreply, load_feed(socket, socket.assigns.next, socket.assigns.items)}
  end

  defp load_feed(%{assigns: %{rep: nil}} = socket, _before, _items),
    do: assign(socket, items: [], days: [], next: nil, summaries: %{}, latest: %{})

  defp load_feed(socket, before, items) do
    %{items: more, next: next} =
      Activity.feed(socket.assigns.rep.person.id,
        filter: elem(socket.assigns.filter, 2),
        before: before
      )

    items = items ++ more

    bill_ids =
      items |> Enum.map(& &1.bill) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id) |> Enum.uniq()

    assign(socket,
      items: items,
      days: Enum.chunk_by(items, & &1.date),
      next: next,
      summaries: Legislation.latest_summaries(bill_ids),
      latest: Legislation.latest_actions(bill_ids)
    )
  end

  defp rep_path(district, rep, filter),
    do: ~p"/reps/#{district}?#{query(rep: rep && rep.person.id, filter: filter)}"

  defp query(pairs),
    do: Enum.reject(pairs, fn {k, v} -> is_nil(v) or (k == :filter and v == "all") end)

  defp party(%{party: party}) when is_binary(party) and party != "", do: String.first(party)
  defp party(_), do: nil

  defp day(date), do: Calendar.strftime(date, "%A, %b %-d")

  defp bill_label(%{identifier: id, title: title}), do: "#{id} · #{title}"

  # "On Passage." before "Passed, 220–207.", but not before a result that already
  # names the question ("Cloture on the Motion to Proceed Rejected").
  defp question_prefix(%{question: q, result: r}) when is_binary(q) and is_binary(r) do
    core = q |> String.replace_prefix("On ", "") |> String.downcase()
    if String.contains?(String.downcase(r), core), do: nil, else: "#{q}. "
  end

  defp question_prefix(%{question: q}) when is_binary(q), do: "#{q}. "
  defp question_prefix(_vote), do: nil

  defp result(vote) do
    tally = "#{vote.yea_count}–#{vote.nay_count}"
    if vote.result, do: "#{vote.result}, #{tally}.", else: "#{tally}."
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :filters, @filters)

    ~H"""
    <Layouts.app flash={@flash} width={:full} current_scope={@current_scope}>
      <%!-- Large screens: reps down a left column beside a 720px feed --%>
      <div class="lg:grid lg:grid-cols-[300px_minmax(0,720px)] lg:justify-center lg:gap-10 lg:pt-8 lg:items-start">
        <section class="pt-5 pb-2 lg:p-0 flex flex-col gap-3 lg:sticky lg:top-4">
          <div class="flex items-baseline justify-between gap-3">
            <.eyebrow>Your representatives · {@district}</.eyebrow>
            <.link navigate={~p"/"} class="py-1 text-[13px] font-medium text-floor-accent">
              Change address
            </.link>
          </div>
          <p :if={@reps == []} class="m-0 text-[15px]">No current members found for {@district}.</p>
          <nav
            :if={@reps != []}
            aria-label="Representatives"
            class="grid gap-2 lg:flex lg:flex-col"
            style={"grid-template-columns: repeat(#{length(@reps)}, minmax(0, 1fr))"}
          >
            <.link
              :for={r <- @reps}
              patch={rep_path(@district, r, nil)}
              aria-current={if r == @rep, do: "page"}
              class={[
                "flex flex-col lg:flex-row items-center gap-1.5 lg:gap-3 px-1.5 py-3 lg:px-3.5 rounded-xl bg-floor-card text-center lg:text-left",
                if(r == @rep, do: "border-2 border-floor-accent", else: "border border-floor-line")
              ]}
            >
              <span
                aria-hidden="true"
                class="size-11 flex-none rounded-full bg-[#e3e6e9] flex items-center justify-center font-semibold text-[15px] text-floor-ink-2"
              >
                {initials(r.person.name)}
              </span>
              <span class="flex flex-col gap-1.5 lg:gap-0.5">
                <span class="text-[14px] lg:text-[15px] font-semibold leading-tight text-floor-ink">
                  {r.person.name}
                </span>
                <span class="text-[12px] lg:text-[13px] text-floor-muted">
                  {r.body.name}{if p = party(r.membership), do: " · #{p}"}
                </span>
              </span>
            </.link>
          </nav>
          <.link
            navigate={~p"/this-week"}
            class="hidden lg:block self-start py-1.5 text-[14px] font-semibold text-floor-accent"
          >
            This week's schedule ›
          </.link>
        </section>

        <div class="min-w-0">
          <section :if={@rep} class="py-3 lg:pt-0 flex flex-col gap-3.5 lg:gap-4">
            <div class="flex flex-col lg:flex-row lg:flex-wrap lg:items-end lg:justify-between gap-3.5 lg:gap-4">
              <div class="flex flex-col gap-1">
                <h1 class="m-0 text-[24px] lg:text-[32px] leading-tight font-bold tracking-tight">
                  {@rep.person.name}
                </h1>
                <p class="m-0 text-[14px] lg:text-[15px] text-floor-muted">
                  {@rep.body.name}{if @rep.membership.party, do: " · #{@rep.membership.party}"} · {@rep.membership.district}
                </p>
              </div>
              <div class="grid grid-cols-2 lg:flex gap-2">
                <.card class="!p-3 lg:!px-4 lg:min-w-[120px]">
                  <p class="m-0 text-[22px] font-bold">{@counts.sponsored}</p>
                  <p class="m-0 mt-0.5 text-[13px] text-floor-muted">bills introduced</p>
                </.card>
                <.card class="!p-3 lg:!px-4 lg:min-w-[120px]">
                  <p class="m-0 text-[22px] font-bold">{@counts.cosponsored}</p>
                  <p class="m-0 mt-0.5 text-[13px] text-floor-muted">bills cosponsored</p>
                </.card>
              </div>
            </div>
            <nav aria-label="Show" class="flex flex-wrap gap-1.5">
              <.link
                :for={{key, label, _} <- @filters}
                patch={rep_path(@district, @rep, key)}
                aria-current={if elem(@filter, 0) == key, do: "page"}
                class={[
                  "flex-none px-3.5 py-2.5 rounded-full text-[14px]",
                  if(elem(@filter, 0) == key,
                    do: "bg-floor-ink text-white font-semibold",
                    else: "bg-floor-card border border-floor-line text-floor-ink font-medium"
                  )
                ]}
              >
                {label}
              </.link>
            </nav>
          </section>

          <section :if={@rep} aria-label="Activity" class="flex flex-col gap-2.5">
            <p :if={@items == []} class="m-0 py-6 text-[15px] text-floor-muted">Nothing yet.</p>
            <%= for items <- @days do %>
              <h2 class="mt-2.5 mb-0 text-[13px] font-semibold text-floor-muted">
                {day(hd(items).date)}
              </h2>
              <.activity_item
                :for={item <- items}
                item={item}
                summary={item.bill && @summaries[item.bill.id]}
                latest={item.bill && @latest[item.bill.id]}
              />
            <% end %>
            <button
              :if={@next}
              type="button"
              phx-click="more"
              class="mt-2 py-3 rounded-xl bg-floor-card border border-floor-line text-[14px] font-semibold text-floor-accent"
            >
              Load more
            </button>
            <.source_line>
              Votes and bills from the official record; every item links to its source.
            </.source_line>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true
  attr :summary, :any, default: nil
  attr :latest, :any, default: nil

  defp activity_item(%{item: %{kind: :vote}} = assigns) do
    ~H"""
    <.card class="flex flex-col gap-2 !p-3.5">
      <div class="flex items-center gap-2">
        <.vote_chip option={@item.option} prefix />
        <span class="text-[13px] text-floor-muted">
          {@item.vote.body && @item.vote.body.name} · {@item.vote.identifier}
        </span>
      </div>
      <p class="m-0 text-[16px] font-semibold leading-snug">
        <a :if={@item.bill} href={~p"/bills/#{@item.bill.external_id}"} class="text-floor-ink">
          {bill_label(@item.bill)}
        </a>
        <span :if={!@item.bill}>{@item.vote.question}</span>
      </p>
      <p class="m-0 text-[14px] text-floor-ink-2">
        {if @item.bill, do: question_prefix(@item.vote)}{result(@item.vote)}
      </p>
    </.card>
    """
  end

  defp activity_item(assigns) do
    ~H"""
    <.card class="flex flex-col gap-2 !p-3.5">
      <span class="text-[13px] font-semibold text-floor-accent">{kind_label(@item.kind)}</span>
      <p class="m-0 text-[16px] font-semibold leading-snug">
        <a href={~p"/bills/#{@item.bill.external_id}"} class="text-floor-ink">{bill_label(@item.bill)}</a>
      </p>
      <p :if={line = item_line(@item, @latest)} class="m-0 text-[14px] text-floor-ink-2">{line}</p>
      <div
        :if={@item.kind in [:moved, :became_law]}
        class="border-t border-floor-line-soft pt-2.5 flex flex-col gap-1.5"
      >
        <.eyebrow class="!text-[12px]">What it would change</.eyebrow>
        <div
          :if={@summary}
          class="text-[14px] leading-relaxed text-floor-ink-2 [&_p]:m-0 [&_p+p]:mt-2"
        >
          {Phoenix.HTML.raw(@summary.html)}
        </div>
        <p :if={@summary} class="m-0 text-[12px] text-floor-muted">
          Summary by the {@summary.author}
        </p>
        <p :if={!@summary} class="m-0 text-[14px] text-floor-muted">No official summary yet.</p>
      </div>
    </.card>
    """
  end

  defp kind_label(:introduced), do: "Introduced a bill"
  defp kind_label(:moved), do: "Their bill moved"
  defp kind_label(:became_law), do: "Became law"

  defp item_line(%{kind: :introduced}, latest), do: latest && latest.description

  defp item_line(%{kind: kind, action: action}, _latest) when kind in [:moved, :became_law],
    do: action.description
end
