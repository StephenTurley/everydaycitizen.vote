defmodule TheFloorWeb.ThisWeekLive do
  @moduledoc """
  What is scheduled in the next seven days: floor items and committee meetings,
  each with its time, body, title and bills, a week at a time (previous and next
  week links). With a saved district, "My reps" narrows it to their bills and
  committees; signed in, "Followed" narrows it to events on followed bills.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Calendar, as: Schedule
  alias TheFloor.Follows
  alias TheFloor.Reps

  @zone "America/New_York"

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, district: session["district"], page_title: "This week")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{current_scope: scope, district: district} = socket.assigns
    signed_in = !!(scope && scope.user)
    from = from_date(params["from"])
    show = show(params, signed_in, district)

    {:noreply,
     assign(socket,
       from: from,
       show: show,
       shows: shows(signed_in, district),
       days: Schedule.week(Reps.jurisdiction(), from, filter(show, scope, district))
     )}
  end

  defp from_date(param) do
    case Date.from_iso8601(param || "") do
      {:ok, date} -> date
      _ -> DateTime.now!(@zone) |> DateTime.to_date()
    end
  end

  defp show(%{"followed" => "1"}, true, _district), do: :followed
  defp show(%{"mine" => "1"}, _signed_in, district) when is_binary(district), do: :mine
  defp show(_params, _signed_in, _district), do: :all

  defp shows(signed_in, district) do
    [{"Everything", :all}] ++
      if(district, do: [{"My reps", :mine}], else: []) ++
      if(signed_in, do: [{"Followed", :followed}], else: [])
  end

  defp filter(:mine, _scope, district),
    do: [people: Enum.map(Reps.for_district(district), & &1.person.id)]

  defp filter(:followed, scope, _district), do: [bills: Follows.followed_bill_ids(scope)]
  defp filter(:all, _scope, _district), do: []

  defp week_path(from, show) do
    params = [from: Date.to_iso8601(from)]

    params =
      case show do
        :mine -> params ++ [mine: "1"]
        :followed -> params ++ [followed: "1"]
        :all -> params
      end

    ~p"/this-week?#{params}"
  end

  defp time(%{all_day: true}), do: "All day"

  defp time(event),
    do: event.start_at |> DateTime.shift_zone!(@zone) |> Calendar.strftime("%-I:%M %p")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width={:full} current_scope={@current_scope}>
      <%!-- Phones: title, then the week and filter, then the days. Large screens:
           title and days in a 720px column, week and filter in a sidebar. --%>
      <div class="flex flex-col lg:grid lg:grid-cols-[minmax(0,720px)_300px] lg:justify-center lg:gap-x-10 lg:pt-8 lg:items-start">
        <section class="pt-5 pb-3 lg:p-0 lg:col-start-1 lg:row-start-1 flex flex-col gap-1">
          <h1 class="m-0 text-[24px] lg:text-[32px] leading-tight font-bold tracking-tight">
            This week
          </h1>
          <p class="m-0 text-[14px] lg:text-[15px] text-floor-muted">
            {Calendar.strftime(@from, "%b %-d")} to {Calendar.strftime(Date.add(@from, 6), "%b %-d")}, Eastern time
          </p>
        </section>

        <aside class="pb-3 lg:p-0 lg:col-start-2 lg:row-start-1 lg:row-span-2 lg:sticky lg:top-4 flex flex-col gap-3 lg:gap-4">
          <section
            aria-label="Week"
            class="flex items-center justify-between gap-2 lg:p-4 lg:bg-floor-card lg:border lg:border-floor-line lg:rounded-xl"
          >
            <.link
              patch={week_path(Date.add(@from, -7), @show)}
              aria-label="Previous week"
              class="px-3.5 py-2.5 rounded-[10px] border border-floor-line bg-floor-card font-semibold text-floor-accent"
            >
              ‹
            </.link>
            <span class="text-[15px] font-semibold">
              {Calendar.strftime(@from, "%b %-d")} – {Calendar.strftime(Date.add(@from, 6), "%b %-d")}
            </span>
            <.link
              patch={week_path(Date.add(@from, 7), @show)}
              aria-label="Next week"
              class="px-3.5 py-2.5 rounded-[10px] border border-floor-line bg-floor-card font-semibold text-floor-accent"
            >
              ›
            </.link>
          </section>
          <section
            :if={length(@shows) > 1}
            aria-label="Show"
            class="flex flex-col gap-2.5 lg:p-4 lg:bg-floor-card lg:border lg:border-floor-line lg:rounded-xl"
          >
            <h2 class="hidden lg:block m-0 text-[15px] font-bold">Show</h2>
            <nav class="flex flex-wrap gap-1.5">
              <.link
                :for={{label, show} <- @shows}
                patch={week_path(@from, show)}
                aria-current={if @show == show, do: "page"}
                class={[
                  "px-3.5 py-2.5 rounded-full text-[14px]",
                  if(@show == show,
                    do: "bg-floor-ink text-white font-semibold",
                    else: "bg-floor-card border border-floor-line font-medium"
                  )
                ]}
              >
                {label}
              </.link>
            </nav>
            <p :if={@district} class="m-0 text-[13px] leading-normal text-floor-muted">
              My reps: Bills your reps sponsor or cosponsor, and meetings of committees they sit on.
            </p>
            <p :if={@show == :followed} class="m-0 text-[13px] leading-normal text-floor-muted">
              Followed: events on bills you follow.
            </p>
          </section>
        </aside>

        <div class="lg:col-start-1 lg:row-start-2 lg:pt-3 min-w-0">
          <p :if={@days == []} class="m-0 py-6 text-[15px] text-floor-muted">Nothing scheduled.</p>

          <section :for={day <- @days} class="flex flex-col gap-2.5 pb-3">
            <h2 class="mt-2 mb-0 text-[13px] font-semibold text-floor-muted">
              {Calendar.strftime(day.date, "%A, %b %-d")}
            </h2>
            <.card
              :for={event <- day.events}
              class="!p-3.5 lg:!px-[18px] lg:!py-4 flex flex-col gap-1.5 lg:grid lg:grid-cols-[88px_minmax(0,1fr)] lg:gap-x-4 lg:gap-y-1"
            >
              <span class="hidden lg:block lg:row-span-3 text-[14px] font-semibold text-floor-ink-2">
                {time(event)}
              </span>
              <span class="text-[13px] text-floor-muted lg:col-start-2">
                <span class="lg:hidden">{time(event)}{if event.body, do: " · "}</span>{if event.body,
                  do: event.body.name}
              </span>
              <p class="m-0 text-[16px] font-semibold leading-snug lg:col-start-2">{event.title}</p>
              <p
                :if={event.event_bills != [] or event.unresolved_bill_labels != []}
                class="m-0 text-[14px] flex flex-wrap gap-x-3 gap-y-1 lg:col-start-2"
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
        </div>
      </div>
    </Layouts.app>
    """
  end
end
