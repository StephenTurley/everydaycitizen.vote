defmodule EverydayCitizenWeb.BillLive do
  @moduledoc """
  The bill page (mockup "Bill page (M2)"): the bill and its sponsor, where it
  stands, the visitor's reps' part in it, the official summary labeled with its
  author, the text by section with a version picker, and its roll calls.

  Opening one section asks for its plain-English summary (`Summaries.request/3`):
  shown from the cache, or written by a job and pushed here over PubSub. "Expand
  all" shows cached summaries only, so it never sets off a whole bill's worth.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.{BillHistory, BillPage, Follows, RateLimit, Reps, Summaries}
  alias EverydayCitizen.Summaries.{Claude, Inputs}

  import EverydayCitizenWeb.BillHistoryComponents

  @repo_url "https://github.com/StephenTurley/everydaycitizen.vote/blob/main/"
  @hour :timer.hours(1)

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
           summary_topics: [],
           history_steps: nil,
           history_rows: nil,
           origins: %{},
           origins_code: nil,
           version_dates: %{},
           change_summary: nil,
           change_topic: nil
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

  def handle_info({:ai_summary, "change", subject, result}, socket) do
    case socket.assigns.change_summary do
      {^subject, _state} ->
        {:noreply, assign(socket, :change_summary, {subject, ai_state(result)})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_info({:ai_summary, "bill", subject, result}, socket) do
    case socket.assigns.bill_summary do
      {^subject, _state} -> {:noreply, assign(socket, :bill_summary, {subject, ai_state(result)})}
      _other -> {:noreply, socket}
    end
  end

  def handle_info({:section_summary, index, {:error, :paused}}, socket),
    do: {:noreply, update(socket, :summaries, &Map.put(&1, index, :paused))}

  def handle_info({:section_summary, index, {:error, _}}, socket),
    do: {:noreply, update(socket, :summaries, &Map.put(&1, index, :unavailable))}

  # Where each section of the version came from (worked out again only when the
  # version changes); for an opened section that changed or was added, the
  # steps that touched it and the reps' part. All versions' sections are read
  # at most once per request, and not at all for an unchanged section.
  defp load_history(socket) do
    {socket, rows} = assign_origins(socket)
    assign_opened(assign(socket, history: nil, history_rows: nil), rows)
  end

  # origins for the version, kept while the version stays the same; returns the
  # versions' sections when it had to read them
  defp assign_origins(%{assigns: %{page: page, version: version}} = socket) do
    code = version && version.code

    cond do
      is_nil(code) ->
        {assign(socket, origins: %{}, origins_code: nil), nil}

      socket.assigns.origins_code == code ->
        {socket, nil}

      true ->
        rows = BillHistory.load(page.bill)

        {assign(socket,
           origins: BillHistory.origins(page.bill, code, rows),
           origins_code: code,
           version_dates: Map.new(BillHistory.versions(page.bill), &{&1.code, &1.date})
         ), rows}
    end
  end

  defp assign_opened(%{assigns: %{page: page, open: open}} = socket, rows) do
    case is_integer(open) && socket.assigns.origins[open] do
      %{status: status} = origin when status != :original ->
        rows = rows || BillHistory.load(page.bill)
        steps = socket.assigns.history_steps || BillHistory.steps(page.bill)

        assign(socket,
          history_steps: steps,
          history_rows: rows,
          history: %{
            index: open,
            origin: origin,
            steps: steps,
            involvement: involvement(change_steps(origin, steps), page.reps),
            comparison: BillHistory.comparison(page.bill, socket.assigns.origins_code, open, rows)
          }
        )

      _ ->
        socket
    end
  end

  # the steps that changed a section (not the version it started in, unless added there)
  defp change_steps(%{status: status, added_in: added_in, changed_in: changed}, steps) do
    codes = if(status == :added, do: [added_in], else: []) ++ changed
    Enum.filter(steps, &(&1.code in codes))
  end

  # each rep's votes and committees across the steps, and whether their chamber
  # voted in them at all
  defp involvement(_steps, []), do: []

  defp involvement(steps, reps) do
    people = Enum.map(reps, & &1.person)
    per_step = Enum.map(steps, &BillHistory.involvement(&1, people))

    chambers =
      for step <- steps,
          vote <- step.votes ++ Enum.map(step.related_votes, & &1.vote),
          into: MapSet.new(),
          do: vote.body_id

    for {rep, i} <- Enum.with_index(reps) do
      parts = Enum.map(per_step, &Enum.at(&1, i))

      %{
        person: rep.person,
        body: rep.body,
        chamber_voted: MapSet.member?(chambers, rep.body.id),
        votes: parts |> Enum.flat_map(& &1.votes) |> Enum.uniq_by(fn {v, _} -> v.id end),
        committees: parts |> Enum.flat_map(& &1.committees) |> Enum.uniq_by(& &1.id)
      }
    end
  end

  # The opened change's explanation: cached, or asked for once the page is live
  # (not by crawlers); none for an unchanged section.
  defp load_change_summary(socket) do
    if topic = socket.assigns.change_topic,
      do: Phoenix.PubSub.unsubscribe(EverydayCitizen.PubSub, topic)

    socket = assign(socket, change_summary: nil, change_topic: nil)

    with %{index: i} <- socket.assigns.history,
         true <- Claude.enabled?(),
         {subject, input} <-
           Inputs.change(socket.assigns.page.bill, socket.assigns.version.code, i) do
      change_summary_state(socket, subject, input)
    else
      _ -> socket
    end
  end

  defp change_summary_state(socket, subject, input) do
    cond do
      summary = Summaries.get_ai(:change, subject, input) ->
        assign(socket, :change_summary, {subject, {:ok, summary.summary}})

      socket.assigns.crawler ->
        socket

      not connected?(socket) ->
        assign(socket, :change_summary, {subject, :loading})

      true ->
        topic = Summaries.ai_topic(:change, subject)
        Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, topic)

        state =
          if RateLimit.hit(
               {:summaries, socket.assigns.remote_ip},
               Summaries.visitor_limit(),
               @hour
             ) ==
               :limited,
             do: :limited,
             else: requested(Summaries.request_ai(:change, subject, input))

        assign(socket, change_summary: {subject, state}, change_topic: topic)
    end
  end

  # The bill's executive summary: cached, or asked for once the page is live
  # (listening first, so one finished in between is not missed).
  defp load_bill_summary(socket) do
    with true <- Claude.enabled?(),
         {subject, input} <- Inputs.bill(socket.assigns.page.bill) do
      case bill_summary_state(socket, subject, input) do
        :none -> assign(socket, :bill_summary, nil)
        state -> assign(socket, :bill_summary, {subject, state})
      end
    else
      _ -> assign(socket, :bill_summary, nil)
    end
  end

  defp bill_summary_state(socket, subject, input) do
    cond do
      summary = Summaries.get_ai(:bill, subject, input) ->
        {:ok, summary.summary}

      socket.assigns.crawler ->
        :none

      not connected?(socket) ->
        :loading

      true ->
        Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.ai_topic(:bill, subject))

        if RateLimit.hit({:summaries, socket.assigns.remote_ip}, Summaries.visitor_limit(), @hour) ==
             :limited,
           do: :limited,
           else: requested(Summaries.request_ai(:bill, subject, input))
    end
  end

  defp ai_state({:ok, text}), do: {:ok, text}
  defp ai_state({:error, :paused}), do: :paused
  defp ai_state({:error, _}), do: :unavailable

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

    state = summary_state(socket, version_id, i, Summaries.section_text(entry), live?)
    socket = keep_listening(socket, topic, live? and state == :loading)

    if state == :disabled, do: socket, else: update(socket, :summaries, &Map.put(&1, i, state))
  end

  defp summary_state(socket, version_id, i, text, live?) do
    cond do
      summary = Summaries.get(version_id, i, text) ->
        {:ok, summary.summary}

      socket.assigns.crawler ->
        :disabled

      not live? ->
        :loading

      RateLimit.hit({:summaries, socket.assigns.remote_ip}, Summaries.visitor_limit(), @hour) ==
          :limited ->
        :limited

      true ->
        requested(Summaries.request(version_id, i, text))
    end
  end

  defp keep_listening(socket, topic, true), do: assign(socket, :summary_topics, [topic])

  defp keep_listening(socket, topic, false) do
    Phoenix.PubSub.unsubscribe(EverydayCitizen.PubSub, topic)
    socket
  end

  defp requested({:cached, summary}), do: {:ok, summary.summary}
  defp requested(:queued), do: :loading
  defp requested(other), do: other

  @impl true
  def handle_event("toggle_follow", _params, socket) do
    {:noreply,
     EverydayCitizenWeb.FollowToggle.toggle(socket, {:bill, socket.assigns.page.bill.id})}
  end

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

  # The summary is of the newest version with text; beside another version it
  # names the one it was written from rather than pointing at the text below.
  defp bill_summary_source(subject, version, versions) do
    [_, _, code] = String.split(subject, ":", parts: 3)
    summarized = Enum.find(versions, &(&1.code == code))

    cond do
      version && version.code == code -> "the bill's text below"
      summarized -> "the “#{summarized.classification || code}” version of this bill"
      true -> "another version of this bill"
    end
  end

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

  attr :index, :integer, required: true
  attr :state, :any, required: true
  attr :prompt_url, :string, required: true
  attr :report, :map, required: true

  # The plain-English summary above a section's text (labeled as AI-written).
  defp section_summary(assigns) do
    ~H"""
    <.ai_box
      id={"summary-#{@index}"}
      class="mx-4 lg:mx-7 mb-3"
      title="In plain English"
      source="the text below"
      state={@state}
      prompt_url={@prompt_url}
      report={@report}
    />
    """
  end

  # What a "Report a problem" form under a summary sends with the report.
  defp report(assigns, kind, subject) do
    %{
      kind: to_string(kind),
      subject: subject,
      prompt_version: Summaries.prompt_version(kind),
      page: assigns.path,
      user: assigns.current_scope && assigns.current_scope.user,
      remote_ip: assigns.remote_ip
    }
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, prompt_url: @repo_url <> Claude.prompt_path(:section), repo_url: @repo_url)

    ~H"""
    <Layouts.app flash={@flash} width={:full} current_scope={@current_scope}>
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
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p :if={@page.sponsor} class="m-0 text-[14px] lg:text-[15px] text-floor-muted">
            Sponsor: {@page.sponsor.name} · {cosponsors(@page.cosponsor_count)}
          </p>
          <.follow_button
            id="follow-bill"
            label="Follow this bill"
            signed_in={!!(@current_scope && @current_scope.user)}
            following={@following}
            return_to={~p"/bills/#{@page.bill.external_id}"}
          />
        </div>
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

          <section aria-label="Votes on this bill" class="order-6 pb-5 lg:pb-0 flex flex-col gap-2.5">
            <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Votes</h2>
            <p :if={@page.votes == []} class="m-0 text-[15px] text-floor-muted">
              No roll-call votes yet.
            </p>
            <.card :for={vote <- @page.votes} class="!p-3.5 flex flex-col gap-0.5">
              <span class="text-[15px] lg:text-[14px] font-semibold">{vote.question} · {vote.result}, {vote.yea_count}–{vote.nay_count}</span>
              <.vote_subject vote={vote} />
              <span class="text-[13px] text-floor-muted">{vote.body.name} · {vote.identifier} · {vote_date(
                vote
              )}</span>
              <.term_note question={vote.question} />
            </.card>
          </section>

          <footer class="order-7 pb-4 flex flex-col gap-2">
            <a
              href={@page.bill.web_url || @page.bill.source.url}
              class="self-start text-[14px] font-semibold text-floor-accent py-1"
            >Official page</a>
            <.source_line>Every item on this page comes from the official record.</.source_line>
          </footer>
        </aside>

        <div class="contents lg:flex lg:flex-col lg:gap-6 lg:col-start-1 xl:col-start-2 lg:row-start-1 lg:min-w-0">
          <section
            :if={match?({_, _}, @bill_summary)}
            aria-label="In plain English"
            class="order-3 lg:order-1 pb-5 lg:pb-0"
          >
            <.ai_box
              id="bill-summary"
              class="bg-floor-card border border-floor-line"
              title="In plain English: what this bill does"
              source={bill_summary_source(elem(@bill_summary, 0), @version, @page.versions)}
              state={elem(@bill_summary, 1)}
              prompt_url={@repo_url <> Claude.prompt_path(:bill)}
              report={report(assigns, :bill, elem(@bill_summary, 0))}
            />
          </section>

          <section aria-label="Official summary" class="order-4 lg:order-3 pb-5 flex flex-col gap-2.5">
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
            class="order-5 lg:order-2 pb-5 flex flex-col gap-3 lg:gap-4"
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
                    <span class="flex flex-col gap-1">
                      <span class="text-[15px] lg:text-[16px]">
                        <strong :if={entry["enum"]} class="font-semibold">Sec. {entry["enum"]}</strong>
                        {entry["heading"]}
                      </span>
                      <.origin_tag origin={@origins[i]} dates={@version_dates} />
                    </span>
                    <span aria-hidden="true" class="text-floor-muted">{toggle(open?(@open, i))}</span>
                  </.link>
                  <.origin_panel
                    :if={@history && @history.index == i}
                    index={i}
                    origin={@history.origin}
                    steps={@history.steps}
                    involvement={@history.involvement}
                    comparison={@history.comparison}
                  >
                    <:explanation>
                      <.ai_box
                        :if={@change_summary}
                        id={"change-summary-#{i}"}
                        title="In plain English: what this change does"
                        source={
                          if @history.origin.status == :added,
                            do: "the section's text below",
                            else: "the two versions below"
                        }
                        state={elem(@change_summary, 1)}
                        prompt_url={@repo_url <> Claude.prompt_path(:change)}
                        report={report(assigns, :change, elem(@change_summary, 0))}
                      />
                    </:explanation>
                  </.origin_panel>
                  <.section_summary
                    :if={open?(@open, i) and Map.has_key?(@summaries, i)}
                    index={i}
                    state={@summaries[i]}
                    prompt_url={@prompt_url}
                    report={report(assigns, :section, "section:#{@version.id}:#{i}")}
                  />
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
