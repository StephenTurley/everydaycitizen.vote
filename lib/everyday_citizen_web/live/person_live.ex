defmodule EverydayCitizenWeb.PersonLive do
  @moduledoc """
  A page for one legislator, current or former (mockup screen 3): who they are
  and the seat they hold or last held, a Follow button, their week (the same
  panel as the reps page), the bills they sponsored and cosponsored, five of
  each with more on request, and their committee seats.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.{Legislation, Legislature, Reps}
  alias EverydayCitizenWeb.RepPanel

  @first 5
  @more 10

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    person = Legislature.get_person(id) || raise EverydayCitizenWeb.NotFoundError
    seat = Legislature.latest_chamber_membership(person.id)
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(
       page_title: person.name,
       person: person,
       rep: Map.merge(%{person: person, membership: nil, body: nil}, seat || %{}),
       since: seat && Legislature.serving_since(person.id, seat.body.id),
       served_until: served_until(seat, today),
       committees: Legislature.committee_roles(person.id, today),
       sponsored: Legislation.sponsored_bills(person.id, "primary", limit: @first),
       cosponsored: Legislation.sponsored_bills(person.id, "cosponsor", limit: @first)
     )
     |> RepPanel.init()}
  end

  # the end of a seat that has ended; nil while it lasts
  defp served_until(%{membership: %{end_date: %Date{} = ended}}, today) do
    if Date.before?(ended, today), do: ended
  end

  defp served_until(_seat, _today), do: nil

  @impl true
  def handle_params(params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    id = socket.assigns.person.id

    {:noreply,
     socket
     |> assign(:path, if(query, do: "#{path}?#{query}", else: path))
     |> RepPanel.assign_rep(socket.assigns.rep, params, &person_path(id, &1, &2))}
  end

  @impl true
  def handle_info(message, socket), do: RepPanel.handle_info(message, socket)

  @impl true
  def handle_event("more_sponsored", _params, socket), do: {:noreply, more(socket, :sponsored)}

  def handle_event("more_cosponsored", _params, socket),
    do: {:noreply, more(socket, :cosponsored)}

  def handle_event(event, params, socket), do: RepPanel.handle_event(event, params, socket)

  defp more(socket, key) do
    %{bills: shown} = socket.assigns[key]
    classification = if key == :sponsored, do: "primary", else: "cosponsor"

    %{bills: next, total: total} =
      Legislation.sponsored_bills(socket.assigns.person.id, classification,
        limit: @more,
        offset: length(shown)
      )

    assign(socket, key, %{bills: shown ++ next, total: total})
  end

  defp person_path(id, filter, week),
    do: ~p"/people/#{id}?#{RepPanel.query(filter: filter, week: week && Date.to_iso8601(week))}"

  defp month(date), do: Calendar.strftime(date, "%b %Y")

  defp seat_line(%{body: nil}), do: nil

  defp seat_line(%{body: body, membership: membership}) do
    [body.name, membership.party, Reps.district_label(membership.district)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp role_label("chair"), do: "Chair"
  defp role_label("vice_chair"), do: "Vice chair"
  defp role_label("ranking_member"), do: "Ranking member"
  defp role_label(_), do: "Member"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-5 pb-3.5 flex flex-col gap-3.5">
        <div class="flex items-center gap-3.5">
          <img
            :if={@person.image_url}
            src={@person.image_url}
            alt=""
            class="size-16 flex-none rounded-full object-cover bg-[#e3e6e9]"
          />
          <span
            :if={!@person.image_url}
            aria-hidden="true"
            class="size-16 flex-none rounded-full bg-[#e3e6e9] flex items-center justify-center font-semibold text-[20px] text-floor-ink-2"
          >
            {initials(@person.name)}
          </span>
          <div class="min-w-0 flex flex-col gap-1">
            <h1 class="m-0 text-[24px] leading-tight font-bold tracking-tight break-words">
              {@person.name}
            </h1>
            <p :if={line = seat_line(@rep)} class="m-0 text-[14px] text-floor-muted">
              {line}{if @since && !@served_until, do: " · since #{month(@since)}"}
            </p>
            <p :if={@served_until} class="m-0 text-[14px] text-floor-muted">
              Served until {month(@served_until)}
            </p>
          </div>
        </div>
        <.follow_button
          id="follow-rep"
          signed_in={!!(@current_scope && @current_scope.user)}
          following={@following}
          return_to={~p"/people/#{@person.id}"}
        />
      </section>

      <RepPanel.rep_panel
        filter={@filter}
        week={@week}
        this_monday={@this_monday}
        panel_path={@panel_path}
        week_summary={@week_summary}
        items={@items}
        days={@days}
        next={@next}
        summaries={@summaries}
        latest={@latest}
        path={@path}
        current_scope={@current_scope}
        remote_ip={@remote_ip}
      />

      <.bill_list
        id="sponsored"
        title="Bills they sponsored"
        event="more_sponsored"
        list={@sponsored}
      />
      <.bill_list
        id="cosponsored"
        title="Bills they cosponsored"
        event="more_cosponsored"
        list={@cosponsored}
      />

      <section id="committees" class="mt-8 flex flex-col gap-2.5">
        <h2 class="m-0 text-[18px] font-bold">Committees</h2>
        <p :if={@committees == []} class="m-0 text-[15px] text-floor-muted">
          No committee seats on record.
        </p>
        <ul :if={@committees != []} class="m-0 p-0 list-none flex flex-col gap-2">
          <li
            :for={c <- @committees}
            class={[
              "flex items-baseline justify-between gap-3 px-3.5 py-3 rounded-xl bg-floor-card border border-floor-line",
              c.body.classification == "subcommittee" && "ml-5"
            ]}
          >
            <span class="min-w-0 text-[15px] font-medium leading-snug">{c.body.name}</span>
            <span class="flex-none text-[13px] text-floor-muted">{role_label(c.role)}</span>
          </li>
        </ul>
        <.source_line>Bills and committee seats from the official record.</.source_line>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :event, :string, required: true
  attr :list, :map, required: true

  defp bill_list(assigns) do
    ~H"""
    <section id={@id} class="mt-8 flex flex-col gap-2.5">
      <h2 class="m-0 text-[18px] font-bold">
        {@title} <span class="font-normal text-floor-muted">· {@list.total}</span>
      </h2>
      <p :if={@list.bills == []} class="m-0 text-[15px] text-floor-muted">None on record.</p>
      <.card :for={%{bill: bill, latest: latest} <- @list.bills} class="flex flex-col gap-1.5 !p-3.5">
        <p class="m-0 text-[16px] font-semibold leading-snug">
          <a href={~p"/bills/#{bill.external_id}"} class="text-floor-ink">
            {bill.identifier} · {bill.title}
          </a>
        </p>
        <p :if={latest} class="m-0 text-[14px] text-floor-ink-2">
          {latest.description}
          <span :if={latest.date} class="text-floor-muted">
            · {Calendar.strftime(latest.date, "%b %-d, %Y")}
          </span>
        </p>
      </.card>
      <button
        :if={length(@list.bills) < @list.total}
        type="button"
        phx-click={@event}
        class="py-3 rounded-xl bg-floor-card border border-floor-line text-[14px] font-semibold text-floor-accent"
      >
        Show more
      </button>
    </section>
    """
  end
end
