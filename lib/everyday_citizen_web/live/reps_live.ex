defmodule EverydayCitizenWeb.RepsLive do
  @moduledoc """
  A district's reps, one at a time (mockup board A): the row of reps, the
  selected rep's header and counts, a week switcher, filters, and that week's
  activity grouped by day, each item linking to its bill page. Above the week's
  items, a plain-English summary of the rep's week, written by AI the first time
  anyone views that week and cached (rewritten when the week gains activity).
  With no week chosen, the page opens on the rep's most recent active week.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.Reps
  alias EverydayCitizenWeb.RepPanel

  @impl true
  def mount(%{"district" => district}, _session, socket) do
    {:ok,
     socket |> assign(district: district, reps: Reps.for_district(district)) |> RepPanel.init()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    socket = assign(socket, :path, if(query, do: "#{path}?#{query}", else: path))
    %{district: district, reps: reps} = socket.assigns
    rep = Enum.find(reps, &(to_string(&1.person.id) == params["rep"])) || List.first(reps)

    {:noreply,
     socket
     |> assign(page_title: rep && rep.person.name)
     |> RepPanel.assign_rep(rep, params, &rep_path(district, rep, &1, &2))}
  end

  @impl true
  def handle_info(message, socket), do: RepPanel.handle_info(message, socket)

  @impl true
  def handle_event(event, params, socket), do: RepPanel.handle_event(event, params, socket)

  defp rep_path(district, rep, filter, week \\ nil),
    do:
      ~p"/reps/#{district}?#{RepPanel.query(rep: rep && rep.person.id, filter: filter, week: week && Date.to_iso8601(week))}"

  defp party(%{party: party}) when is_binary(party) and party != "", do: String.first(party)
  defp party(_), do: nil

  @impl true
  def render(assigns) do
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
          <section :if={@rep} class="pt-3 pb-3.5 lg:pt-0 lg:pb-4 flex flex-col">
            <div class="flex flex-col lg:flex-row lg:flex-wrap lg:items-end lg:justify-between gap-3.5 lg:gap-4">
              <div class="flex flex-col gap-1">
                <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
                  <h1 class="m-0 text-[24px] lg:text-[32px] leading-tight font-bold tracking-tight">
                    {@rep.person.name}
                  </h1>
                  <.follow_button
                    id="follow-rep"
                    signed_in={!!(@current_scope && @current_scope.user)}
                    following={@following}
                    return_to={rep_path(@district, @rep, nil)}
                  />
                </div>
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
          </section>
          <RepPanel.rep_panel
            :if={@rep}
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
        </div>
      </div>
    </Layouts.app>
    """
  end
end
