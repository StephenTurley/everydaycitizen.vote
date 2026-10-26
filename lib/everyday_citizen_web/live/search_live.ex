defmodule EverydayCitizenWeb.SearchLive do
  @moduledoc """
  The search results page (mockup screens 1 and 2), reached from the header's
  search box. Its groups come in a fixed order: the place named, if any, then
  bills with the number typed, bills with this name, bills whose text mentions
  it (ten to a page), then the people whose names match. An empty group is
  left out.

  The query is classified again here, so a hand-typed address in the URL is
  never searched, echoed or put in a link, and the URL is replaced by a bare
  `/search`. Results show only AI summaries that
  are already cached; searching never starts one. The page is `noindex`.

  A search runs once the page is connected, never on the first (static)
  render, and each visitor may run a limited number a minute
  (`config :everyday_citizen, :search, per_minute:`): past it, the page asks
  them to wait and runs no query.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.{RateLimit, Reps, Search}
  alias EverydayCitizen.Search.Query
  alias EverydayCitizenWeb.SearchController

  @names 10
  @people 20
  @page_size 10
  # the text search counts at most 1,000 matches: 100 pages
  @max_page 100
  @minute :timer.minutes(1)

  @stages %{
    law: "Became law",
    passed: "Passed a chamber",
    voted: "Had a roll-call vote",
    reported: "Reported by committee",
    introduced: "Introduced"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       noindex: true,
       page_title: "Search",
       remote_ip: EverydayCitizenWeb.RemoteIp.from_socket(socket)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case classify(params["q"]) do
      {:search, query} ->
        {:noreply, socket |> assign(query: query) |> search(page(params["page"]))}

      # a hand-typed address leaves the address bar: the page moves to a bare
      # /search and remembers (in a flash no toast shows) to say why
      :address ->
        {:noreply,
         socket
         |> put_flash(:address, "1")
         |> push_patch(to: ~p"/search", replace: true)}

      :empty ->
        kind = if Phoenix.Flash.get(socket.assigns.flash, :address), do: :address, else: :empty
        {:noreply, assign(socket, kind: kind, query: nil)}
    end
  end

  # a hand-made URL can carry q as a list or map; that is nothing typed. A
  # state and ZIP shaped like a bill number no bill has is an address.
  defp classify(q) when is_binary(q) do
    case Query.classify(q) do
      {:search, query} = search -> if Search.address_like?(query), do: :address, else: search
      other -> other
    end
  end

  defp classify(_q), do: :empty

  # The static render runs no query: it would be a search no per-visitor limit
  # can count (its visitor's address is unknown until connected).
  defp search(socket, page) do
    cond do
      not connected?(socket) ->
        assign(socket, kind: :searching)

      RateLimit.hit({:search, socket.assigns.remote_ip}, per_minute(), @minute) == :limited ->
        assign(socket, kind: :limited)

      true ->
        socket |> assign(kind: :search) |> run_search(page)
    end
  end

  defp per_minute, do: Application.get_env(:everyday_citizen, :search, [])[:per_minute] || 60

  defp run_search(socket, page) do
    query = socket.assigns.query

    numbered = numbered(Search.bill_by_number(query))
    named = Search.bills_by_name(query, @names)
    found = Enum.map(numbered, & &1.id) ++ Enum.map(named, & &1.bill.id)
    text = Search.bills_by_text(query, found, page)
    people = Search.people(query, @people)

    place = if people.place && people.place.reps != [], do: people.place

    assign(socket,
      page: page,
      numbered: numbered,
      named: named,
      text: text,
      place: place,
      people: people.people,
      nothing?:
        Enum.all?([numbered, named, text.results, List.wrap(place), people.people], &(&1 == [])),
      searchable?: Search.text_searchable?(query)
    )
  end

  # a typed URL can name a single bill's number (the search box goes straight to it)
  defp numbered({:one, bill}), do: [bill]
  defp numbered({:many, bills}), do: bills
  defp numbered(:none), do: []

  # a page number from the URL, 1 to the last page there can be
  defp page(param) when is_binary(param) do
    case Integer.parse(param) do
      {n, ""} -> n |> max(1) |> min(@max_page)
      _ -> 1
    end
  end

  defp page(_param), do: 1

  defp stage(stage), do: Map.fetch!(@stages, stage)

  defp results_path(query, 1), do: ~p"/search?#{[q: query.text]}"
  defp results_path(query, page), do: ~p"/search?q=#{query.text}&page=#{page}"

  defp seat_line(%{body: nil}), do: nil

  defp seat_line(%{body: body, membership: membership}) do
    [body.name, membership.party, Reps.district_label(membership.district)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  # the summary's opening paragraph: results show a taste, the bill page the rest
  defp opening(summary) do
    summary
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.find("", &(&1 != "" and not String.starts_with?(&1, ["#", "- "])))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      query={if @kind in [:search, :searching, :limited], do: @query.text, else: ""}
    >
      <div class="pt-5 flex flex-col gap-6">
        <%= case @kind do %>
          <% :address -> %>
            <p class="m-0 text-[15px]">
              <.link navigate={~p"/"} class="font-semibold text-floor-accent underline">
                {SearchController.address_message()}
              </.link>
            </p>
          <% :empty -> %>
            <p class="m-0 text-[15px] text-floor-muted">
              Search for a bill by its number or name, a phrase in its text, or a person by name or place.
            </p>
          <% :searching -> %>
            <p class="m-0 text-[15px] text-floor-muted">Searching…</p>
          <% :limited -> %>
            <p class="m-0 text-[15px]">Too many searches. Wait a minute and try again.</p>
          <% :search -> %>
            <p :if={@nothing?} class="m-0 text-[15px]">
              Nothing matched “{@query.text}”.
              <%= if @searchable? do %>
                Check the spelling, or search for a bill number or a person's name.
              <% else %>
                Try more specific words.
              <% end %>
            </p>

            <%!-- a place named outright is what was meant: its members come first --%>
            <.group :if={@place} label={@place.name}>
              <.person_item :for={rep <- @place.reps} rep={rep} />
            </.group>

            <.group :if={@numbered != []} label={"Bills numbered #{@query.number || @query.text}"}>
              <.bill_item :for={bill <- @numbered} bill={bill} title={bill.title} />
            </.group>

            <.group :if={@named != []} label="Bills with this name">
              <.bill_item
                :for={r <- @named}
                bill={r.bill}
                title={r.title}
                stage={r.stage}
                summary={r.summary}
              />
            </.group>

            <.group :if={@text.results != []} label="Bills whose text mentions it">
              <.bill_item
                :for={r <- @text.results}
                bill={r.bill}
                title={r.bill.title}
                stage={r.stage}
                excerpt={r.excerpt}
              />
              <div class="flex justify-between gap-4 text-[14px] font-semibold">
                <.link
                  :if={@page > 1}
                  patch={results_path(@query, @page - 1)}
                  class="text-floor-accent"
                >
                  Previous page
                </.link>
                <.link
                  :if={@text.more?}
                  patch={results_path(@query, @page + 1)}
                  class="ml-auto text-floor-accent"
                >
                  {@text.total - @page * page_size()} more bills mention it
                </.link>
              </div>
            </.group>

            <.group :if={@people != []} label="People">
              <.person_item :for={rep <- @people} rep={rep} />
            </.group>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp page_size, do: @page_size

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp group(assigns) do
    ~H"""
    <section aria-label={@label} class="flex flex-col gap-2">
      <h2 class="m-0 text-[12px] font-bold tracking-wide uppercase text-floor-muted">{@label}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :bill, :map, required: true
  attr :title, :string, required: true
  attr :stage, :atom, default: nil
  attr :summary, :string, default: nil
  attr :excerpt, :map, default: nil

  defp bill_item(assigns) do
    ~H"""
    <.card class="flex flex-col gap-1 !px-3.5 !py-3 min-w-0">
      <span class="text-[13px] font-semibold text-floor-muted break-words">
        {@bill.identifier}{if @excerpt && @excerpt.section, do: " · #{@excerpt.section}"}
      </span>
      <a
        href={~p"/bills/#{@bill.external_id}"}
        class="text-[16px] font-semibold leading-snug text-floor-accent break-words"
      >
        {@title}
      </a>
      <span :if={@stage} class="text-[13px] text-floor-muted">{stage(@stage)}</span>
      <p
        :if={@excerpt && @excerpt.parts != []}
        class="m-0 font-serif text-[15px] leading-snug text-floor-ink-2 break-words"
      >
        “…<%= for {kind, text} <- @excerpt.parts do %>
          <mark
            :if={kind == :mark}
            class="bg-[#fdf0b8] text-floor-ink px-0.5"
          >{text}</mark><span :if={kind == :text}>{text}</span>
        <% end %>…”
      </p>
      <.story_line
        :if={(groups = story_groups(@summary)) != []}
        class="mt-1 pl-2 border-l-[3px] border-floor-line"
        group={hd(groups)}
      />
      <div
        :if={story_groups(@summary) == [] && @summary && opening(@summary) != ""}
        class="mt-1 pl-2 border-l-[3px] border-floor-line text-[14px] text-floor-ink-2"
      >
        <span class="block text-[12px] text-floor-muted">
          Written by AI from the bill; it can be wrong
        </span>
        {opening(@summary)}
      </div>
    </.card>
    """
  end

  attr :rep, :map, required: true

  defp person_item(assigns) do
    ~H"""
    <.card class="flex items-center gap-2.5 !px-3.5 !py-3 min-w-0">
      <img
        :if={@rep.person.image_url}
        src={@rep.person.image_url}
        alt=""
        class="size-10 flex-none rounded-full object-cover bg-[#e3e6e9]"
      />
      <span
        :if={!@rep.person.image_url}
        aria-hidden="true"
        class="size-10 flex-none rounded-full bg-[#e3e6e9] flex items-center justify-center font-semibold text-[13px] text-floor-ink-2"
      >
        {initials(@rep.person.name)}
      </span>
      <div class="min-w-0 flex flex-col">
        <a
          href={~p"/people/#{@rep.person.id}"}
          class="text-[16px] font-semibold text-floor-accent break-words"
        >
          {@rep.person.name}
        </a>
        <span :if={line = seat_line(@rep)} class="text-[13px] text-floor-muted">{line}</span>
      </div>
    </.card>
    """
  end
end
