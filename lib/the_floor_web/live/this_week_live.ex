defmodule TheFloorWeb.ThisWeekLive do
  @moduledoc """
  What is scheduled in the next seven days: floor items and committee meetings,
  each with its time, body, title and bills. With a saved district, "My reps"
  narrows it to their bills and committees.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Calendar, as: Schedule
  alias TheFloor.Reps

  @zone "America/New_York"

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, district: session["district"], page_title: "This week")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    from =
      case Date.from_iso8601(params["from"] || "") do
        {:ok, date} -> date
        _ -> DateTime.now!(@zone) |> DateTime.to_date()
      end

    mine = params["mine"] == "1" and socket.assigns.district != nil
    people = if mine, do: Enum.map(Reps.for_district(socket.assigns.district), & &1.person.id)
    days = Schedule.week(Reps.jurisdiction(), from, if(people, do: [people: people], else: []))

    {:noreply, assign(socket, from: from, mine: mine, days: days)}
  end

  defp week_path(from, mine),
    do:
      ~p"/this-week?#{Enum.reject([from: Date.to_iso8601(from), mine: mine && "1"], &(!elem(&1, 1)))}"

  defp time(%{all_day: true}), do: "All day"

  defp time(event),
    do: event.start_at |> DateTime.shift_zone!(@zone) |> Calendar.strftime("%-I:%M %p")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pt-5 pb-3 flex flex-col gap-3">
        <h1 class="m-0 text-[24px] font-bold tracking-tight">This week</h1>
        <p class="m-0 text-[14px] text-floor-muted">
          {Calendar.strftime(@from, "%b %-d")} to {Calendar.strftime(Date.add(@from, 6), "%b %-d")}, Eastern time
        </p>
        <nav :if={@district} aria-label="Show" class="flex gap-1.5">
          <.link
            :for={{label, mine} <- [{"Everything", false}, {"My reps", true}]}
            patch={week_path(@from, mine)}
            aria-current={if @mine == mine, do: "page"}
            class={[
              "px-3.5 py-2.5 rounded-full text-[14px]",
              if(@mine == mine,
                do: "bg-floor-ink text-white font-semibold",
                else: "bg-floor-card border border-floor-line font-medium"
              )
            ]}
          >
            {label}
          </.link>
        </nav>
      </section>

      <p :if={@days == []} class="m-0 py-6 text-[15px] text-floor-muted">Nothing scheduled.</p>

      <section :for={day <- @days} class="flex flex-col gap-2.5 pb-3">
        <h2 class="mt-2 mb-0 text-[13px] font-semibold text-floor-muted">
          {Calendar.strftime(day.date, "%A, %b %-d")}
        </h2>
        <.card :for={event <- day.events} class="!p-3.5 flex flex-col gap-1.5">
          <span class="text-[13px] text-floor-muted">
            {time(event)}{if event.body, do: " · #{event.body.name}"}
          </span>
          <p class="m-0 text-[16px] font-semibold leading-snug">{event.title}</p>
          <p
            :if={event.event_bills != [] or event.unresolved_bill_labels != []}
            class="m-0 text-[14px] flex flex-wrap gap-x-3 gap-y-1"
          >
            <a
              :for={eb <- event.event_bills}
              href={~p"/bills/#{eb.bill.external_id}"}
              class="font-semibold text-floor-accent"
            >
              {eb.bill.identifier}
            </a>
            <span :for={label <- event.unresolved_bill_labels} class="text-floor-ink-2">{label}</span>
          </p>
        </.card>
      </section>

      <.source_line>Floor and committee schedules from the official calendars.</.source_line>
    </Layouts.app>
    """
  end
end
