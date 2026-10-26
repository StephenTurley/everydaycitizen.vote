defmodule EverydayCitizenWeb.RepPanel do
  @moduledoc """
  One rep's week, shared by the reps page and a person's page: a week switcher,
  filters, and that week's activity grouped by day, each item linking to its
  bill page. Above the week's items, a plain-English summary of the rep's week,
  written by AI the first time anyone views that week and cached (rewritten
  when the week gains activity). With no week chosen, it opens on the rep's most
  recent active week.

  A LiveView calls `init/1` in mount, `assign_rep/4` in handle_params, hands
  `handle_info/2` and `handle_event/3` the messages and events below, and
  renders `rep_panel/1`.
  """
  use EverydayCitizenWeb, :html

  alias EverydayCitizen.{Activity, Follows, Legislation, Reps}
  alias EverydayCitizen.Summaries.Inputs
  alias EverydayCitizenWeb.AiSummary

  @zone "America/New_York"

  @filters [
    {"all", "Everything", :all},
    {"votes", "Votes", :votes},
    {"bills", "Their bills", :bills},
    {"law", "Became law", :law}
  ]

  @doc "The assigns the panel needs from mount, while connect info is still readable."
  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    assign(socket,
      remote_ip: EverydayCitizenWeb.RemoteIp.from_socket(socket),
      crawler: EverydayCitizenWeb.Crawler.crawler?(socket),
      week_summary: nil
    )
  end

  @doc """
  Shows `rep` (or nothing, for nil) with the week and filter the params ask
  for. `path` builds the page's own link for a filter key and a week (either
  may be nil), so the week switcher and filters stay on the calling page.
  """
  @spec assign_rep(
          Phoenix.LiveView.Socket.t(),
          Reps.rep() | nil,
          map(),
          (String.t() | nil, Date.t() | nil -> String.t())
        ) :: Phoenix.LiveView.Socket.t()
  def assign_rep(socket, rep, params, path) do
    filter = Enum.find(@filters, {"all", "Everything", :all}, &(elem(&1, 0) == params["filter"]))

    socket
    |> assign(rep: rep, filter: filter, panel_path: path)
    |> assign(week: rep && week(params["week"], rep), this_monday: this_monday())
    |> assign(counts: rep && Activity.counts(rep.person.id))
    |> assign(
      following:
        !!rep && Follows.following?(socket.assigns.current_scope, {:person, rep.person.id})
    )
    |> load_feed(nil, [])
    |> load_week_summary()
  end

  @doc "A week summary finished writing."
  def handle_info({:ai_summary, "rep_week", subject, result}, socket),
    do: {:noreply, AiSummary.put_result(socket, :week_summary, subject, result)}

  @doc "`toggle_follow` follows or unfollows the rep; `more` loads the next page of the week."
  def handle_event("toggle_follow", _params, %{assigns: %{rep: %{} = rep}} = socket),
    do: {:noreply, EverydayCitizenWeb.FollowToggle.toggle(socket, {:person, rep.person.id})}

  def handle_event("more", _params, socket) do
    {:noreply, load_feed(socket, socket.assigns.next, socket.assigns.items)}
  end

  @doc "Query pairs for a panel link, leaving out empty values and the default filter."
  @spec query(keyword()) :: keyword()
  def query(pairs),
    do: Enum.reject(pairs, fn {k, v} -> is_nil(v) or (k == :filter and v == "all") end)

  defp this_monday, do: DateTime.now!(@zone) |> DateTime.to_date() |> Date.beginning_of_week()

  # The Monday of the week to show: the one asked for (not in the future), else
  # the rep's most recent active week, else this week.
  defp week(param, rep) do
    with {:ok, date} <- Date.from_iso8601(param || ""),
         false <- Date.after?(date, DateTime.now!(@zone) |> DateTime.to_date()) do
      Date.beginning_of_week(date)
    else
      _ -> latest_week(rep)
    end
  end

  defp latest_week(rep) do
    case Activity.latest_date(rep.person.id) do
      nil -> this_monday()
      date -> Date.beginning_of_week(date)
    end
  end

  defp week_label(monday),
    do:
      "#{Calendar.strftime(monday, "%b %-d")} – #{Calendar.strftime(Date.add(monday, 6), "%b %-d")}"

  # The week's summary (see `AiSummary`); none for a week with nothing on the record.
  defp load_week_summary(socket) do
    AiSummary.load(socket, :week_summary, :rep_week, fn ->
      with %{rep: %{} = rep, week: %Date{} = week} <- socket.assigns,
           {subject, input} when is_binary(input) <- Inputs.rep_week(rep.person.id, week) do
        {subject, input}
      else
        _ -> nil
      end
    end)
  end

  defp load_feed(%{assigns: %{rep: nil}} = socket, _before, _items),
    do: assign(socket, items: [], days: [], next: nil, summaries: %{}, latest: %{})

  defp load_feed(socket, before, items) do
    %{items: more, next: next} =
      Activity.feed(socket.assigns.rep.person.id,
        filter: elem(socket.assigns.filter, 2),
        before: before,
        from: socket.assigns.week,
        to: Date.add(socket.assigns.week, 6)
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

  @doc "The week switcher, filters, the week's summary and its activity."
  attr :filter, :any, required: true
  attr :week, Date, required: true
  attr :this_monday, Date, required: true
  attr :panel_path, :any, required: true, doc: "the page's link for a filter key and a week"
  attr :week_summary, :any, required: true
  attr :items, :list, required: true
  attr :days, :list, required: true
  attr :next, :any, required: true
  attr :summaries, :map, required: true
  attr :latest, :map, required: true
  attr :path, :string, required: true, doc: "the current page, for problem reports"
  attr :current_scope, :any, required: true
  attr :remote_ip, :any, required: true

  def rep_panel(assigns) do
    assigns = assign(assigns, filters: @filters)

    ~H"""
    <section class="pb-3 flex flex-col gap-3.5 lg:gap-4">
      <div id="week" class="flex items-center gap-2">
        <.link
          patch={@panel_path.(elem(@filter, 0), Date.add(@week, -7))}
          aria-label="Previous week"
          class="px-3 py-2 rounded-[10px] border border-floor-line bg-floor-card font-semibold text-floor-accent"
        >
          ‹
        </.link>
        <span class="text-[15px] font-semibold">{week_label(@week)}</span>
        <.link
          :if={Date.compare(@week, @this_monday) == :lt}
          patch={@panel_path.(elem(@filter, 0), Date.add(@week, 7))}
          aria-label="Next week"
          class="px-3 py-2 rounded-[10px] border border-floor-line bg-floor-card font-semibold text-floor-accent"
        >
          ›
        </.link>
      </div>
      <nav aria-label="Show" class="flex flex-wrap gap-1.5">
        <.link
          :for={{key, label, _} <- @filters}
          patch={@panel_path.(key, @week)}
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

    <section aria-label="Activity" class="flex flex-col gap-2.5">
      <.ai_box
        :if={@week_summary}
        id="week-summary"
        class="bg-floor-card border border-floor-line"
        title="In plain English: this week"
        source="this week's record below"
        state={elem(@week_summary, 1)}
        prompt_url={AiSummary.prompt_url(:rep_week)}
        report={AiSummary.report(assigns, :rep_week, elem(@week_summary, 0))}
      />
      <p :if={@items == []} class="m-0 py-6 text-[15px] text-floor-muted">
        Nothing on the record for this week.
      </p>
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
        <span :if={!@item.bill}>{@item.vote.description || @item.vote.question}</span>
      </p>
      <.vote_subject :if={@item.bill} vote={@item.vote} />
      <p class="m-0 text-[14px] text-floor-ink-2">
        {if @item.bill || @item.vote.description, do: question_prefix(@item.vote)}{result(@item.vote)}
      </p>
      <.term_note id={"term-#{@item.vote.id}"} question={@item.vote.question} />
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
