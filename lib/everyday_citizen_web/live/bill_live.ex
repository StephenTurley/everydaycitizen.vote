defmodule EverydayCitizenWeb.BillLive do
  @moduledoc """
  The bill page: the bill and its sponsor, where it stands, the visitor's reps'
  part in it, the AI story of the bill (`FloorComponents.bill_story/1`) beside
  the official summary labeled with its author, the text by section with a
  version picker and each section's history, and its roll calls.

  AI text comes through `AiSummary`: the bill's story, the explanation of what
  changed from the previous version, and each section's summary when the
  section is opened. Each is shown from the cache or written by a job and
  pushed here over PubSub. "Expand all" shows cached section summaries only, so
  it never sets off a whole bill's worth.

  This module holds the page's state: the version and open section from the
  URL, the text's history, the summaries and the votes' positions once opened.
  What it shows is in `BillPageComponents` (header, where it stands, reps,
  votes, the AI story, the official summary) and `BillTextComponents` (the
  text by section).
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.{BillHistory, BillPage, Follows, Reps, Summaries}
  alias EverydayCitizen.Summaries.{Claude, Inputs}
  alias EverydayCitizenWeb.AiSummary

  import EverydayCitizenWeb.{BillPageComponents, BillTextComponents}

  @impl true
  def mount(%{"id" => id}, session, socket) do
    district = session["district"]
    reps = if district, do: Reps.for_district(district), else: []

    case BillPage.load(Reps.jurisdiction(), id, reps) do
      {:ok, page} ->
        {:ok,
         assign(socket,
           page: page,
           district: district,
           page_title: page.bill.identifier,
           following: Follows.following?(socket.assigns.current_scope, {:bill, page.bill.id}),
           remote_ip: EverydayCitizenWeb.RemoteIp.from_socket(socket),
           crawler: EverydayCitizenWeb.Crawler.crawler?(socket),
           summaries: %{},
           positions: %{},
           summary_topics: [],
           history_steps: nil,
           history_rows: nil,
           origins: %{},
           origins_code: nil,
           version_dates: %{},
           change_summary: nil
         )
         |> load_bill_summary()}

      :not_found ->
        raise EverydayCitizenWeb.NotFoundError
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, URI.parse(uri).path)
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

    socket =
      socket
      |> assign(version: version, sections: Enum.with_index(sections), open: open)
      |> load_history()
      |> load_summaries()
      |> load_change_summary()
      # the versions' sections are only needed during this request
      |> assign(:history_rows, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:section_summary, index, {:ok, text}}, socket),
    do: {:noreply, update(socket, :summaries, &Map.put(&1, index, {:ok, text}))}

  def handle_info({:ai_summary, "change", subject, result}, socket),
    do: {:noreply, AiSummary.put_result(socket, :change_summary, subject, result)}

  def handle_info({:ai_summary, "bill", subject, result}, socket),
    do: {:noreply, AiSummary.put_result(socket, :bill_summary, subject, result)}

  def handle_info({:section_summary, index, {:error, :paused}}, socket),
    do: {:noreply, update(socket, :summaries, &Map.put(&1, index, :paused))}

  def handle_info({:section_summary, index, {:error, _}}, socket),
    do: {:noreply, update(socket, :summaries, &Map.put(&1, index, :unavailable))}

  # Where each section of the version came from, as stored (read again only
  # when the version changes); for an opened section that changed or was added,
  # the steps that touched it and the reps' part. That panel reads every
  # version's text, so only once the page is live: not twice per visit, and
  # never for a crawler (which never connects).
  defp load_history(socket) do
    socket = socket |> assign_origins() |> assign(history: nil, history_rows: nil)
    if connected?(socket), do: assign_opened(socket), else: socket
  end

  # origins for the version, kept while the version stays the same
  defp assign_origins(%{assigns: %{page: page, version: version}} = socket) do
    code = version && version.code

    if socket.assigns.origins_code == code do
      socket
    else
      assign(socket,
        origins: BillPage.origins(page.bill, code),
        origins_code: code,
        version_dates: Map.new(page.versions, &{&1.code, &1.date})
      )
    end
  end

  defp assign_opened(%{assigns: %{page: page, open: open}} = socket) do
    case is_integer(open) && socket.assigns.origins[open] do
      %{status: status} = origin when status != :original ->
        rows = BillHistory.load(page.bill)
        steps = socket.assigns.history_steps || BillHistory.steps(page.bill)

        assign(socket,
          history_steps: steps,
          history_rows: rows,
          history: %{
            index: open,
            origin: origin,
            steps: steps,
            involvement: BillHistory.rep_involvement(origin, steps, page.reps),
            comparison: BillHistory.comparison(page.bill, socket.assigns.origins_code, open, rows)
          }
        )

      _ ->
        socket
    end
  end

  # The opened change's explanation: cached, or asked for once the page is live
  # (not by crawlers); none for an unchanged section.
  defp load_change_summary(socket) do
    AiSummary.load(socket, :change_summary, :change, fn ->
      case socket.assigns.history do
        %{index: i} -> Inputs.change(socket.assigns.page.bill, socket.assigns.version.code, i)
        _ -> nil
      end
    end)
  end

  # The bill's executive summary.
  defp load_bill_summary(socket),
    do:
      AiSummary.load(socket, :bill_summary, :bill, fn -> Inputs.bill(socket.assigns.page.bill) end)

  # The summaries to show for the open section(s). Pages stop listening for the
  # sections they showed before (another version or section).
  defp load_summaries(socket) do
    for topic <- socket.assigns.summary_topics,
        do: Phoenix.PubSub.unsubscribe(EverydayCitizen.PubSub, topic)

    socket = assign(socket, summaries: %{}, summary_topics: [])

    if socket.assigns.version && Claude.enabled?(),
      do: summaries_for(socket, socket.assigns.open),
      else: socket
  end

  defp summaries_for(socket, :all) do
    sections =
      for {%{"kind" => "section"} = entry, i} <- socket.assigns.sections,
          do: {i, Summaries.section_text(entry)}

    cached =
      socket.assigns.version.id
      |> Summaries.get_many(sections)
      |> Map.new(fn {i, summary} -> {i, {:ok, summary.summary}} end)

    assign(socket, :summaries, cached)
  end

  defp summaries_for(socket, i) when is_integer(i) do
    case Enum.find(socket.assigns.sections, fn {_entry, n} -> n == i end) do
      {%{"kind" => "section"} = entry, _} -> request_summary(socket, i, entry)
      _ -> socket
    end
  end

  defp summaries_for(socket, _closed), do: socket

  # Listens for the section's summary before asking for it, so one finished in
  # between is not missed; stops listening if no job will answer.
  defp request_summary(socket, i, entry) do
    version_id = socket.assigns.version.id
    topic = Summaries.topic(version_id, i)
    live? = connected?(socket)
    if live?, do: Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, topic)

    state = summary_state(socket, version_id, i, Summaries.section_text(entry))
    socket = keep_listening(socket, topic, live? and state == :loading)

    if state == :disabled, do: socket, else: update(socket, :summaries, &Map.put(&1, i, state))
  end

  defp summary_state(socket, version_id, i, text) do
    case AiSummary.state(socket, Summaries.get(version_id, i, text), fn ->
           Summaries.request(version_id, i, text)
         end) do
      :none -> :disabled
      state -> state
    end
  end

  defp keep_listening(socket, topic, true), do: assign(socket, :summary_topics, [topic])

  defp keep_listening(socket, topic, false) do
    Phoenix.PubSub.unsubscribe(EverydayCitizen.PubSub, topic)
    socket
  end

  @impl true
  def handle_event("toggle_follow", _params, socket) do
    {:noreply,
     EverydayCitizenWeb.FollowToggle.toggle(socket, {:bill, socket.assigns.page.bill.id})}
  end

  # Roll calls have hundreds of names, so each is read when first opened.
  def handle_event("positions", %{"vote" => vote_id}, socket) do
    with {id, ""} <- Integer.parse(vote_id),
         true <- Enum.any?(socket.assigns.page.votes, &(&1.id == id)),
         false <- Map.has_key?(socket.assigns.positions, id) do
      {:noreply, update(socket, :positions, &Map.put(&1, id, BillPage.vote_positions(id)))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("version", %{"version" => code}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/bills/#{socket.assigns.page.bill.external_id}?#{[version: code]}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} width={:full} current_scope={@current_scope}>
      <%!-- From lg the band's white runs edge to edge (the ::before), past the
           1280px column --%>
      <.bill_header
        bill={@page.bill}
        sponsor={@page.sponsor}
        cosponsors={@page.cosponsors}
        cosponsor_count={@page.cosponsor_count}
        district={@district}
        signed_in={!!(@current_scope && @current_scope.user)}
        following={@following}
      />

      <%!-- Phones: one column in the order below (`order-*`; the two wrappers are
           `contents`). lg: text and summary | sidebar. xl: contents | text | sidebar. --%>
      <div class="flex flex-col lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(280px,320px)] xl:grid-cols-[220px_minmax(0,720px)_minmax(280px,340px)] lg:gap-10 lg:pt-7 lg:items-start">
        <.bill_contents
          :if={@sections != []}
          bill={@page.bill}
          version={@version}
          sections={@sections}
          open={@open}
        />

        <aside class="contents lg:flex lg:flex-col lg:gap-4 lg:col-start-2 xl:col-start-3 lg:row-start-1 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
          <.where_it_stands steps={@page.steps} latest_action={@page.latest_action} />

          <.reps_on_bill :if={@page.reps != []} reps={@page.reps} />

          <.bill_votes votes={@page.votes} positions={@positions} />

          <footer class="order-7 pb-4 flex flex-col gap-2">
            <a
              href={@page.bill.web_url || @page.bill.source.url}
              class="self-start text-[14px] font-semibold text-floor-accent py-1"
            >Official page</a>
            <.source_line>Every item on this page comes from the official record.</.source_line>
          </footer>
        </aside>

        <div class="contents lg:flex lg:flex-col lg:gap-6 lg:col-start-1 xl:col-start-2 lg:row-start-1 lg:min-w-0">
          <.bill_story_section
            :if={match?({_, _}, @bill_summary)}
            summary={@bill_summary}
            bill={@page.bill}
            version={@version}
            versions={@page.versions}
            sections={@sections}
            origins={@origins}
            version_dates={@version_dates}
            report={AiSummary.report(assigns, :bill, elem(@bill_summary, 0))}
          />

          <.official_summary summary={@page.summary} />

          <.bill_text
            bill={@page.bill}
            versions={@page.versions}
            version={@version}
            sections={@sections}
            open={@open}
            origins={@origins}
            version_dates={@version_dates}
            history={@history}
            change_summary={@change_summary}
            summaries={@summaries}
            report={&AiSummary.report(assigns, &1, &2)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
