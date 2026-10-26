defmodule EverydayCitizenWeb.BillPageComponents do
  @moduledoc """
  The parts of the bill page around its text: the header with the sponsor and
  the follow button, where the bill stands, the visitor's reps' part in it,
  its roll calls, the AI-written story of the bill (with the parts later
  versions added), and the official summary labeled with its author.
  """
  use EverydayCitizenWeb, :html

  alias EverydayCitizen.BillHistory
  alias EverydayCitizen.Summaries.Story
  alias EverydayCitizenWeb.AiSummary

  attr :bill, :map, required: true
  attr :sponsor, :map, default: nil
  attr :cosponsors, :list, required: true
  attr :cosponsor_count, :integer, required: true
  attr :district, :string, default: nil
  attr :signed_in, :boolean, required: true
  attr :following, :boolean, required: true

  @doc "The bill's identifier, title, sponsor and cosponsors, and the follow button."
  def bill_header(assigns) do
    ~H"""
    <section class="relative z-0 -mx-5 px-5 lg:-mx-10 lg:px-10 pt-4 pb-5 lg:pt-5 lg:pb-7 bg-floor-card border-b border-floor-line lg:bg-transparent lg:border-b-0 lg:before:absolute lg:before:inset-y-0 lg:before:left-1/2 lg:before:w-screen lg:before:-translate-x-1/2 lg:before:-z-10 lg:before:bg-floor-card lg:before:border-b lg:before:border-floor-line flex flex-col gap-2.5">
      <.link
        :if={@district}
        navigate={~p"/reps/#{@district}"}
        class="self-start text-[14px] font-medium text-floor-accent py-1"
      >
        ‹ Back to your reps
      </.link>
      <.eyebrow>{@bill.identifier}</.eyebrow>
      <h1 class="m-0 text-[26px] lg:text-[34px] lg:max-w-[920px] leading-tight font-bold tracking-tight">
        {@bill.title}
      </h1>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div
          :if={@sponsor}
          class="flex flex-col gap-1 text-[14px] lg:text-[15px] text-floor-muted"
        >
          <p class="m-0">
            Sponsor: <.person_link person={@sponsor} />
            <span :if={@cosponsors == []}>· {cosponsors(@cosponsor_count)}</span>
          </p>
          <details
            :if={@cosponsors != []}
            id="cosponsors"
            class="group"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary class="list-none cursor-pointer py-1 text-floor-accent font-medium [&::-webkit-details-marker]:hidden">
              <.disclosure_mark />{cosponsors(@cosponsor_count)}
            </summary>
            <ul class="m-0 mt-1 p-0 list-none flex flex-col gap-1">
              <li :for={person <- @cosponsors}>
                <.person_link person={person} />
              </li>
            </ul>
          </details>
        </div>
        <.follow_button
          id="follow-bill"
          label="Follow this bill"
          signed_in={@signed_in}
          following={@following}
          return_to={~p"/bills/#{@bill.external_id}"}
        />
      </div>
    </section>
    """
  end

  attr :steps, :list, required: true
  attr :latest_action, :map, default: nil

  @doc "The bill's steps (a bar on phones, a list on wide screens) and its latest action."
  def where_it_stands(assigns) do
    ~H"""
    <section
      aria-label="Where it stands"
      class="order-1 py-5 lg:p-[18px] lg:bg-floor-card lg:border lg:border-floor-line lg:rounded-xl flex flex-col gap-3.5 lg:gap-3"
    >
      <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Where it stands</h2>
      <ol
        class="m-0 p-0 list-none grid gap-1 lg:hidden"
        style={"grid-template-columns: repeat(#{length(@steps)}, minmax(0, 1fr))"}
      >
        <li
          :for={step <- @steps}
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
          :for={step <- @steps}
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
      <p :if={@latest_action} class="m-0 text-[15px] lg:text-[14px] leading-relaxed">
        {@latest_action.description}{if @latest_action.date,
          do: " (#{date(@latest_action.date)})"}
      </p>
    </section>
    """
  end

  attr :reps, :list, required: true

  @doc "Each of the visitor's reps with their part in the bill."
  def reps_on_bill(assigns) do
    ~H"""
    <section
      aria-label="Your reps on this bill"
      class="order-2 pb-5 lg:pb-0"
    >
      <.card class="flex flex-col gap-3">
        <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Your reps on this bill</h2>
        <div :for={rep <- @reps} class="flex items-center justify-between gap-2">
          <div class="flex flex-col gap-0.5">
            <span class="text-[15px] lg:text-[14px] font-semibold"><.person_link person={rep.person} /></span>
            <span :if={note = rep_note(rep)} class="text-[13px] text-floor-muted">{note}</span>
          </div>
          <.vote_chip option={rep.state} />
        </div>
      </.card>
    </section>
    """
  end

  attr :votes, :list, required: true
  attr :positions, :map, required: true, doc: "vote id => [{option, people}], once opened"

  @doc "The bill's roll calls, each with who voted how folded away."
  def bill_votes(assigns) do
    ~H"""
    <section aria-label="Votes on this bill" class="order-6 pb-5 lg:pb-0 flex flex-col gap-2.5">
      <h2 class="m-0 text-[18px] lg:text-[17px] font-bold">Votes</h2>
      <p :if={@votes == []} class="m-0 text-[15px] text-floor-muted">
        No roll-call votes yet.
      </p>
      <.card :for={vote <- @votes} class="!p-3.5 flex flex-col gap-0.5">
        <span class="text-[15px] lg:text-[14px] font-semibold">{vote.question} · {vote.result}, {vote.yea_count}–{vote.nay_count}</span>
        <.vote_subject vote={vote} />
        <span class="text-[13px] text-floor-muted">{vote.body.name} · {vote.identifier} · {vote_date(
          vote
        )}</span>
        <.term_note id={"term-#{vote.id}"} question={vote.question} />
        <details
          id={"vote-positions-#{vote.id}"}
          class="group mt-1.5"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary
            phx-click="positions"
            phx-value-vote={vote.id}
            class="list-none cursor-pointer py-1 text-[13px] font-semibold text-floor-accent [&::-webkit-details-marker]:hidden"
          >
            <.disclosure_mark />Who voted how
          </summary>
          <div
            :for={{option, people} <- Map.get(@positions, vote.id, [])}
            class="mt-2 flex flex-col gap-1"
          >
            <span class="text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
              {option_label(option)} · {length(people)}
            </span>
            <ul
              id={"vote-positions-list-#{vote.id}-#{option}"}
              class="m-0 p-0 list-none columns-2 gap-4 text-[14px]"
            >
              <li :for={person <- people}><.person_link person={person} /></li>
            </ul>
          </div>
        </details>
      </.card>
    </section>
    """
  end

  attr :summary, :any, required: true, doc: "`{subject, state}` from `AiSummary.load/4`"
  attr :bill, :map, required: true
  attr :version, :map, default: nil
  attr :versions, :list, required: true
  attr :sections, :list, required: true
  attr :origins, :map, required: true
  attr :version_dates, :map, required: true
  attr :report, :map, required: true

  @doc "The AI-written story of the bill, with the parts later versions added."
  def bill_story_section(assigns) do
    ~H"""
    <section aria-label="If this becomes law" class="order-3 lg:order-1 pb-5 lg:pb-0">
      <.bill_story
        id="bill-summary"
        class="bg-floor-card border border-floor-line"
        title="In plain English: what this bill does"
        source={bill_summary_source(elem(@summary, 0), @version, @versions)}
        state={elem(@summary, 1)}
        prompt_url={AiSummary.prompt_url(:bill)}
        report={@report}
        added={added_parts(assigns)}
      />
    </section>
    """
  end

  attr :summary, :map, default: nil

  @doc "The official summary, folded, labeled with its author."
  def official_summary(assigns) do
    ~H"""
    <section aria-label="Official summary" class="order-4 lg:order-3 pb-5 flex flex-col gap-2.5">
      <%= if @summary do %>
        <%!-- folded by default: the plain-English summary above comes first --%>
        <details
          id="official-summary"
          class="group flex flex-col gap-2.5"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary class="list-none cursor-pointer flex items-center justify-between gap-3 py-1">
            <span class="flex flex-col gap-0.5">
              <h2 class="m-0 text-[18px] lg:text-[22px] font-bold">Official summary</h2>
              <span class="text-[13px] text-floor-muted">
                Written by the {@summary.author}.
              </span>
            </span>
            <span aria-hidden="true" class="text-floor-muted group-open:hidden">+</span>
            <span aria-hidden="true" class="text-floor-muted hidden group-open:inline">−</span>
          </summary>
          <.card class="mt-2.5 text-[15px] leading-relaxed text-floor-ink-2 [&_p]:m-0 [&_p+p]:mt-2 [&_ul]:list-disc [&_ul]:pl-5">
            {Phoenix.HTML.raw(@summary.html)}
          </.card>
        </details>
      <% else %>
        <h2 class="m-0 text-[18px] lg:text-[22px] font-bold">Official summary</h2>
        <p class="m-0 text-[15px] text-floor-muted">No official summary yet.</p>
      <% end %>
    </section>
    """
  end

  defp step_when(%{state: :current}), do: "Now"
  defp step_when(%{skipped: true}), do: "Skipped"
  defp step_when(%{date: %Date{} = d}), do: date(d)
  defp step_when(_step), do: "—"

  defp date(d), do: short_date(d)

  defp vote_date(vote), do: date(vote.voted_on)

  defp option_label("yea"), do: "Yea"
  defp option_label("nay"), do: "Nay"
  defp option_label("present"), do: "Present"
  defp option_label("absent"), do: "Not voting"

  attr :person, :map, required: true
  attr :class, :string, default: nil

  defp person_link(assigns) do
    ~H"""
    <.link navigate={~p"/people/#{@person.id}"} class={["text-floor-accent hover:underline", @class]}>
      {@person.name}
    </.link>
    """
  end

  defp cosponsors(1), do: "1 cosponsor"
  defp cosponsors(n), do: "#{n} cosponsors"

  defp rep_note(%{state: :sponsor}), do: "Sponsor of this bill"
  defp rep_note(%{state: :cosponsor}), do: "Cosponsor of this bill"
  defp rep_note(%{state: :no_vote, body: body}), do: "The #{body.name} hasn't voted"

  defp rep_note(%{state: :unrecorded, body: body, passed_on: date}),
    do: "The #{body.name} passed it without a recorded vote, #{date(date)}"

  defp rep_note(%{vote: vote}) when not is_nil(vote), do: "#{vote.question}, #{vote_date(vote)}"
  defp rep_note(_), do: nil

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

  # The summary's subjects that later versions added, from the text's history
  # (only beside the version the summary was written from)
  defp added_parts(%{summary: {subject, {:ok, text}}, version: %{code: code}} = assigns) do
    if String.ends_with?(subject, ":" <> code) do
      text
      |> Story.split()
      |> Map.fetch!(:subjects)
      |> BillHistory.added_subjects(Enum.map(assigns.sections, &elem(&1, 0)), assigns.origins)
      |> Enum.map(fn %{name: name, added_in: added_in} ->
        %{
          name: name,
          href: ~p"/bills/#{assigns.bill.external_id}?version=#{added_in}",
          date: full_date(assigns.version_dates[added_in])
        }
      end)
    else
      []
    end
  end

  defp added_parts(_assigns), do: []

  defp full_date(nil), do: "a later date"
  defp full_date(d), do: Calendar.strftime(d, "%b %-d, %Y")
end
