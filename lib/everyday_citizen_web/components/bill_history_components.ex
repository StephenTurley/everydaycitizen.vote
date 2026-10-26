defmodule EverydayCitizenWeb.BillHistoryComponents do
  @moduledoc """
  The bill page's text history: each section's origin tag, and for a changed or
  added section the panel saying where it came from (the steps that changed it,
  with committee steps, amendments, and votes on the bill and its procedural
  measures), the reader's reps' part, the change marked in the text and folded
  plain definitions. Facts from the record only, never reasons.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: EverydayCitizenWeb.Endpoint,
    router: EverydayCitizenWeb.Router

  @committee_labels %{
    "referred" => "Referred to",
    "markup" => "Marked up by",
    "reported" => "Reported by"
  }

  attr :origin, :map, default: nil
  attr :dates, :map, required: true

  @doc "A section's origin: since introduced, changed (with the last change's date) or added."
  def origin_tag(assigns) do
    ~H"""
    <span
      :if={@origin}
      class={[
        "inline-flex items-center gap-1.5 text-[12px] whitespace-nowrap",
        tag_class(@origin.status)
      ]}
    >
      <span aria-hidden="true" class={["w-[7px] h-[7px] rounded-full", dot_class(@origin.status)]}></span>
      {tag_text(@origin, @dates)}
    </span>
    """
  end

  defp tag_text(%{status: :original}, _dates), do: "Since introduced"

  defp tag_text(%{status: :changed, changed_in: changed}, dates),
    do: "Changed#{date_suffix(dates[List.last(changed)], " · ")}"

  defp tag_text(%{status: :added, added_in: code}, dates),
    do: "Added#{date_suffix(dates[code], " ")}"

  defp date_suffix(nil, _sep), do: ""
  defp date_suffix(date, sep), do: sep <> EverydayCitizenWeb.FloorComponents.short_date(date)

  defp tag_class(:original), do: "text-floor-muted"
  defp tag_class(:changed), do: "text-[#8a5410] font-semibold"
  defp tag_class(:added), do: "text-floor-accent font-semibold"

  defp dot_class(:original), do: "bg-[#9aa3ad]"
  defp dot_class(:changed), do: "bg-[#c77d1a]"
  defp dot_class(:added), do: "bg-floor-accent"

  attr :index, :integer, required: true
  attr :origin, :map, required: true
  attr :steps, :list, required: true
  attr :involvement, :list, required: true
  attr :comparison, :map, default: nil
  slot :explanation

  @doc "Where a changed or added section came from."
  def origin_panel(assigns) do
    assigns =
      assign(assigns,
        shown: shown_steps(assigns.origin, assigns.steps),
        first: List.first(assigns.steps)
      )

    ~H"""
    <section
      id={"origin-#{@index}"}
      aria-label="Where this section came from"
      class="mx-4 lg:mx-7 mb-3 px-4 py-3.5 rounded-xl bg-floor-card border border-floor-line flex flex-col gap-3.5 font-sans"
    >
      <h3 class="m-0 text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
        Where this section came from
      </h3>

      <p :if={@origin.status == :added and @first} class="m-0 text-[14px] font-semibold">
        Not in the first version ({@first.classification || @first.code}{date_suffix(
          @first.date,
          ", "
        )}).
      </p>

      <ol class="m-0 p-0 list-none flex flex-col gap-3">
        <li :for={step <- @shown} class="grid grid-cols-[14px_minmax(0,1fr)] gap-2.5">
          <span
            aria-hidden="true"
            class={["mt-1.5 w-2.5 h-2.5 rounded-full", step_dot(step, @origin)]}
          ></span>
          <div class="flex flex-col gap-1.5 text-[14px] text-floor-ink-2">
            <span class="text-[13px] font-semibold text-floor-ink">
              {if step.date, do: Calendar.strftime(step.date, "%b %-d, %Y") <> " · "}{step.classification ||
                step.code}
            </span>
            <span :for={a <- Enum.reject(step.committees, &(&1.kind == "other"))}>
              {committee_label(a.kind)} {(a.body && a.body.name) || a.body_ref}{date_suffix(
                a.date,
                ", "
              )}
            </span>
            <span
              :if={Enum.any?(step.committees, &(&1.kind in ["markup", "reported"]))}
              class="text-[13px] text-floor-muted"
            >
              Committee members' individual votes aren't in our records.
            </span>
            <span :for={amdt <- step.amendments}>
              <strong class="font-semibold text-floor-ink">{amdt.identifier}</strong>: {amdt.description ||
                amdt.latest_action}
              <a :if={amdt.url} href={amdt.url} class="ml-1 font-semibold text-floor-accent">
                Official page ›
              </a>
            </span>
            <span :for={rv <- step.related_votes}>
              {related_label(rv)}: {vote_line(rv.vote)}
            </span>
            <span :for={vote <- step.votes}>{vote_line(vote)}</span>
          </div>
        </li>
      </ol>

      {render_slot(@explanation)}

      <div :if={@comparison} id={"comparison-#{@index}"} class="flex flex-col gap-2">
        <span class="text-[13px] font-semibold">What changed in the text</span>
        <div class="font-serif text-[15px] leading-[1.6] flex flex-col gap-2">
          <p :for={paragraph <- collapse(@comparison.paragraphs)} class="m-0">
            <%= for {op, text} <- paragraph do %>
              <del :if={op == :del} class="bg-[#fbe3e1] text-[#8a2a22]">{text}</del><ins
                :if={op == :ins}
                class="bg-[#e1f1e8] text-[#1d5b39] no-underline"
              >{text}</ins><span :if={op == :eq}>{text}</span><span
                :if={op == :gap}
                class="text-floor-muted"
              >{text}</span>
            <% end %>
          </p>
        </div>
      </div>

      <div :if={@involvement != []} class="border-t border-floor-line-soft pt-3 flex flex-col gap-2.5">
        <span class="text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
          Your reps and this section
        </span>
        <div
          :for={rep <- @involvement}
          data-rep
          class="flex flex-col gap-1 text-[14px] text-floor-ink-2"
        >
          <span class="font-semibold text-floor-ink">
            <.link navigate={~p"/people/#{rep.person.id}"} class="text-floor-accent hover:underline">
              {rep.person.name}
            </.link>
          </span>
          <span :for={{vote, option} <- rep.votes}>
            <strong class="font-semibold">{String.capitalize(option)}</strong>
            on {vote_label(vote)} · {vote.identifier}
          </span>
          <span :for={body <- rep.committees}>Sits on {body.name}, which acted on this change.</span>
          <span :if={rep.votes == [] and rep.committees == []} class="text-floor-muted">
            {if rep.chamber_voted,
              do: "No recorded vote on this change.",
              else: "The #{rep.body.name} hasn't voted on this change."}
          </span>
        </div>
      </div>

      <details
        :if={considered_adopted?(@shown)}
        id={"origin-#{@index}-considered-adopted"}
        class="text-[13px] text-floor-ink-2"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="cursor-pointer text-floor-muted">
          What does "considered adopted" mean?
        </summary>
        <p class="m-0 mt-1">
          When a chamber approves a rule that says a change is "considered adopted", the change becomes part of the bill as soon as the rule passes, without a separate vote on the change itself.
        </p>
      </details>
      <details
        :if={Enum.any?(@shown, fn s -> Enum.any?(s.committees, &(&1.kind == "markup")) end)}
        id={"origin-#{@index}-markup"}
        class="text-[13px] text-floor-ink-2"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="cursor-pointer text-floor-muted">What is a markup?</summary>
        <p class="m-0 mt-1">
          A markup is a committee meeting where members go through a bill and vote on changes before sending it to the full chamber.
        </p>
      </details>
    </section>
    """
  end

  @doc "The steps that touched a section: where it began and each change."
  def shown_steps(%{added_in: added_in, changed_in: changed}, steps) do
    codes = [added_in | changed]
    Enum.filter(steps, &(&1.code in codes))
  end

  defp committee_label(kind), do: @committee_labels[kind]

  defp step_dot(step, origin) do
    cond do
      step.code == origin.added_in and origin.status == :added -> "bg-floor-accent"
      step.code == origin.added_in -> "bg-[#9aa3ad]"
      true -> "bg-[#c77d1a]"
    end
  end

  defp related_label(%{vote: %{bill: %{identifier: id}}}) when is_binary(id), do: id
  defp related_label(%{ref: ref}), do: ref

  defp vote_line(vote) do
    tally = "#{vote.yea_count}–#{vote.nay_count}"
    result = if vote.result, do: "#{vote.result}, #{tally}", else: tally
    "#{vote.question} — #{result} · #{vote.identifier}"
  end

  defp vote_label(%{bill: %{identifier: id}, question: q}) when is_binary(id), do: "#{id} (#{q})"
  defp vote_label(%{question: q}), do: q

  defp considered_adopted?(steps),
    do:
      Enum.any?(steps, fn s ->
        Enum.any?(s.amendments, &((&1.description || "") =~ ~r/considered (as )?adopted/i))
      end)

  # Unchanged clauses become one "…" line, except a single short one kept for context.
  defp collapse(paragraphs) do
    paragraphs
    |> Enum.chunk_by(&unchanged?/1)
    |> Enum.flat_map(fn
      [[{:eq, text}]] = run when byte_size(text) <= 160 ->
        run

      [first | _] = run ->
        if unchanged?(first), do: [[{:gap, gap_label(length(run))}]], else: run
    end)
  end

  defp gap_label(1), do: "… 1 unchanged passage …"
  defp gap_label(n), do: "… #{n} unchanged passages …"

  defp unchanged?([{:eq, _}]), do: true
  defp unchanged?(_paragraph), do: false
end
