defmodule EverydayCitizenWeb.FloorComponents do
  @moduledoc """
  The site's page pieces, drawn from the approved mockups: cards, vote chips
  (solid Yea, outlined Nay, gray otherwise: told apart by fill and label, never
  by color alone), section headings and the closing source line.
  """
  use Phoenix.Component

  alias EverydayCitizen.Summaries.Story
  alias Phoenix.LiveView.JS

  @doc "A white card with the hairline border."
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["bg-floor-card border border-floor-line rounded-xl p-4", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A vote position chip. `option` is `yea`, `nay`, `present` or `absent`, or one of
  the bill-page states (`no_vote`, `not_in_office`, `sponsor`, `cosponsor`);
  `prefix` adds "Voted".
  """
  attr :option, :any, required: true
  attr :prefix, :boolean, default: false

  def vote_chip(assigns) do
    assigns = assign(assigns, :label, chip_label(assigns.option, assigns.prefix))

    ~H"""
    <span class={[
      "inline-block rounded-md text-[13px] font-bold leading-5 whitespace-nowrap",
      chip_style(@option)
    ]}>
      {@label}
    </span>
    """
  end

  @labels %{
    "yea" => "Yea",
    "nay" => "Nay",
    "present" => "Present",
    "absent" => "Not voting",
    "no_vote" => "No vote yet",
    "not_in_office" => "Not in office",
    "sponsor" => "Sponsor",
    "cosponsor" => "Cosponsor"
  }

  defp chip_label(option, prefix?) do
    option = to_string(option)
    label = Map.fetch!(@labels, option)
    if prefix? and option in ["yea", "nay", "present"], do: "Voted " <> label, else: label
  end

  defp chip_style(option) when option in ["yea", :sponsor, "sponsor"],
    do: "px-2.5 py-0.5 bg-floor-ink text-white"

  defp chip_style("nay"),
    do: "px-2 py-px bg-floor-card border-[1.5px] border-floor-ink text-floor-ink"

  defp chip_style(_), do: "px-2.5 py-0.5 bg-floor-line-soft text-floor-ink-2 font-semibold"

  @doc "A small uppercase heading (dates, labels)."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <p class={["m-0 text-[13px] font-semibold tracking-wide uppercase text-floor-muted", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc "The closing line naming a page's sources."
  slot :inner_block, required: true

  def source_line(assigns) do
    ~H"""
    <p class="mt-6 text-xs leading-relaxed text-floor-muted">{render_slot(@inner_block)}</p>
    """
  end

  @doc "Initials for a person avatar placeholder."
  def initials(name) do
    name
    |> String.split(~r/[\s-]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 2 or String.ends_with?(&1, ".")))
    |> then(fn parts -> [List.first(parts), List.last(parts)] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  Follow / Following for a bill or a rep. Signed in, it toggles (`toggle_follow`
  event, `aria-pressed`); signed out, it links to sign-in and back to `return_to`.
  """
  attr :id, :string, required: true
  attr :signed_in, :boolean, required: true
  attr :following, :boolean, default: false
  attr :return_to, :string, required: true
  attr :label, :string, default: "Follow"

  def follow_button(assigns) do
    ~H"""
    <button
      :if={@signed_in}
      type="button"
      id={@id}
      phx-click="toggle_follow"
      aria-pressed={to_string(@following)}
      class={[
        "self-start px-4 py-2.5 rounded-xl text-[15px] font-semibold whitespace-nowrap",
        if(@following,
          do: "bg-floor-card border border-floor-ink text-floor-ink",
          else: "bg-floor-ink text-white"
        )
      ]}
    >
      {if @following, do: "Following", else: @label}
    </button>
    <.link
      :if={!@signed_in}
      id={@id}
      href={"/users/sign-in-to?" <> URI.encode_query(to: @return_to)}
      class="self-start px-4 py-2.5 rounded-xl bg-floor-ink text-white text-[15px] font-semibold whitespace-nowrap"
    >
      {@label}
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :title, :string, required: true
  attr :source, :string, required: true
  attr :state, :any, required: true
  attr :prompt_url, :string, required: true
  attr :clamp, :boolean, default: false, doc: "on phones, cut the summary to two lines"

  attr :report, :map,
    default: nil,
    doc:
      "what a \"Report a problem\" form sends (kind, subject, prompt_version, page, user, remote_ip)"

  @doc """
  A plain-English AI summary box: `title`, the summary (paragraphs; lines
  starting "- " as a list; lines starting "## " head a part, and the
  "For example" part is set apart as made up) labeled "Written by AI from <source>; it can be
  wrong" with a link to the published prompt, or a state line while it is being
  written, paused, limited, too long or unavailable.
  """
  def ai_box(assigns) do
    ~H"""
    <div
      id={@id}
      class={["px-4 py-3 rounded-xl bg-floor-ground flex flex-col gap-1.5", @class]}
    >
      <p class="m-0 text-[12px] font-semibold uppercase tracking-wide text-floor-muted">
        {@title}
      </p>
      <%= case @state do %>
        <% {:ok, text} -> %>
          <.summary_body text={Story.without_meta(text)} clamp={@clamp} />
          <p class="m-0 text-[12px] text-floor-muted">
            Written by AI from {@source}; it can be wrong.
            <a href={@prompt_url} class="underline">How it's written</a>
          </p>
          <.live_component
            :if={@report}
            module={EverydayCitizenWeb.FeedbackForm}
            id={"#{@id}-report"}
            report={Map.put(@report, :summary, text)}
          />
        <% :loading -> %>
          <p class="m-0 text-[14px] text-floor-muted">Writing a plain-English summary…</p>
        <% :paused -> %>
          <p class="m-0 text-[14px] text-floor-muted">
            Plain-English summaries are paused for today.
          </p>
        <% :limited -> %>
          <p class="m-0 text-[14px] text-floor-muted">
            You've opened many sections; summaries will be back within the hour.
          </p>
        <% :too_long -> %>
          <p class="m-0 text-[14px] text-floor-muted">This section is too long to summarize.</p>
        <% _unavailable -> %>
          <p class="m-0 text-[14px] text-floor-muted">A summary isn't available right now.</p>
      <% end %>
    </div>
    """
  end

  attr :text, :string, required: true
  attr :clamp, :boolean, default: false

  # A summary's parts: paragraphs, lists, "## " headings, the example set apart.
  defp summary_body(assigns) do
    ~H"""
    <%!-- clamped, the parts' boxes give way on phones so the two-line
               clamp counts their lines --%>
    <div class={[
      "text-[15px] leading-relaxed text-floor-ink",
      if(@clamp,
        do: "max-lg:line-clamp-2 lg:flex lg:flex-col lg:gap-2",
        else: "flex flex-col gap-2"
      )
    ]}>
      <div
        :for={{heading, parts} <- summary_sections(@text)}
        data-part={heading == "For example" && "example"}
        class={[
          "flex flex-col gap-1.5",
          @clamp && "max-lg:contents",
          heading == "For example" &&
            "mt-1 px-3 py-2.5 rounded-lg border border-dashed border-floor-line bg-floor-card"
        ]}
      >
        <h3 :if={heading} class="m-0 mt-1 text-[13px] font-semibold text-floor-muted">
          {heading}
        </h3>
        <%= for part <- parts do %>
          <ul :if={match?({:list, _}, part)} class="m-0 pl-5 list-disc flex flex-col gap-1">
            <li :for={item <- elem(part, 1)}>{item}</li>
          </ul>
          <p :if={match?({:para, _}, part)} class="m-0">{elem(part, 1)}</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :title, :string, required: true
  attr :source, :string, required: true
  attr :state, :any, required: true
  attr :prompt_url, :string, required: true
  attr :report, :map, default: nil

  attr :added, :list,
    default: [],
    doc: "subjects added after the first version: %{name, date, href} (not AI-written)"

  @doc """
  A bill's AI summary led by its story: "If this becomes law", one card per
  group the bill affects, then the made-up example and the full summary folded
  away. A summary without a story part, or any other state, is an `ai_box`.
  """
  def bill_story(assigns) do
    assigns = assign(assigns, :story, story(assigns.state))

    ~H"""
    <%= if @story do %>
      <div id={@id} class={["px-4 py-3 rounded-xl flex flex-col gap-3", @class]}>
        <.story_tags tags={@story.tags} subjects={length(@story.subjects)} />
        <h2 class="m-0 text-[18px] font-bold">If this becomes law</h2>
        <div class="flex flex-col gap-2.5">
          <div
            :for={group <- @story.groups}
            class="bg-floor-card border border-floor-line rounded-xl px-4 py-3.5 flex flex-col gap-1"
          >
            <p class="m-0 font-bold">{group.label}</p>
            <p class="m-0 text-[15px] leading-relaxed">{group.sentence}</p>
          </div>
        </div>
        <p class="m-0 text-[12px] text-floor-muted">
          Written by AI from {@source}; it can be wrong.
          <a href={@prompt_url} class="underline">How it's written</a>
        </p>
        <p :for={part <- @added} class="m-0 text-[14px] text-floor-ink-2">
          The {part.name} part was added in the <.link
            navigate={part.href}
            class="text-floor-accent underline"
          >version of {part.date}</.link>.
        </p>
        <details
          :if={length(@story.subjects) > 1}
          id={@id <> "-subjects"}
          class="group bg-floor-card border border-floor-line-soft rounded-xl px-4"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary class="list-none cursor-pointer min-h-11 flex items-center font-bold [&::-webkit-details-marker]:hidden">
            <.disclosure_mark />All {length(@story.subjects)} subjects
          </summary>
          <ul class="m-0 pb-3 pl-5 list-disc flex flex-col gap-1 text-[15px]">
            <li :for={subject <- @story.subjects}>{subject.name}</li>
          </ul>
        </details>
        <details
          :if={@story.example}
          id={@id <> "-example"}
          class="group bg-floor-card border border-floor-line-soft rounded-xl px-4"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary class="list-none cursor-pointer min-h-11 flex items-center font-bold [&::-webkit-details-marker]:hidden">
            <.disclosure_mark />A made-up example
          </summary>
          <div class="pb-3 text-[15px] leading-relaxed">
            <.summary_body text={@story.example} />
          </div>
        </details>
        <details
          :if={@story.rest != ""}
          id={@id <> "-full"}
          class="group bg-floor-card border border-floor-line-soft rounded-xl px-4"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary class="list-none cursor-pointer min-h-11 flex items-center font-bold [&::-webkit-details-marker]:hidden">
            <.disclosure_mark />The full summary
          </summary>
          <div class="pb-3">
            <.summary_body text={@story.rest} />
          </div>
        </details>
        <.live_component
          :if={@report}
          module={EverydayCitizenWeb.FeedbackForm}
          id={"#{@id}-report"}
          report={Map.put(@report, :summary, elem(@state, 1))}
        />
      </div>
    <% else %>
      <.ai_box
        id={@id}
        class={@class}
        title={@title}
        source={@source}
        state={@state}
        prompt_url={@prompt_url}
        report={@report}
      />
    <% end %>
    """
  end

  attr :tags, :list, default: []
  attr :subjects, :integer, default: 0

  # A story's tags, one style for all, and how many unrelated things it does
  defp story_tags(assigns) do
    ~H"""
    <p :if={@tags != [] or @subjects > 1} class="m-0 text-[12px] font-semibold text-floor-muted">
      {Enum.join(@tags, " · ")}<span :if={@tags != [] and @subjects > 1}> · </span><span :if={
        @subjects > 1
      }>Does {@subjects} unrelated things</span>
    </p>
    """
  end

  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :tags, :list, default: []
  attr :group, :map, required: true, doc: "%{label, sentence}, the first of a bill's story"
  attr :more, :integer, default: 0, doc: "how many more groups the bill page shows"
  attr :href, :string, default: nil
  attr :prompt_url, :string, default: nil
  attr :report, :map, default: nil, doc: "as `ai_box`'s; the form sends `text`, the whole reply"
  attr :text, :string, default: nil

  @doc """
  A bill's story in one line, for a list: its first group's label and sentence,
  "+N more groups" linking to the bill page, and the AI label.
  """
  def story_line(assigns) do
    ~H"""
    <div id={@id} class={["flex flex-col gap-1", @class]}>
      <.story_tags tags={@tags} />
      <p class="m-0 text-[15px] leading-relaxed text-floor-ink">
        <span class="font-bold">{@group.label}:</span> {@group.sentence}
      </p>
      <.link
        :if={@more > 0 && @href}
        navigate={@href}
        class="self-start text-[13px] font-semibold text-floor-accent hover:underline"
      >
        +{@more} more {if @more == 1, do: "group", else: "groups"}
      </.link>
      <p class="m-0 text-[12px] text-floor-muted">
        Written by AI from the bill; it can be wrong<a
          :if={@prompt_url}
          href={@prompt_url}
          class="ml-1 underline"
        >How it's written</a>
      </p>
      <.live_component
        :if={@report && @text}
        module={EverydayCitizenWeb.FeedbackForm}
        id={"#{@id}-report"}
        report={Map.put(@report, :summary, @text)}
      />
    </div>
    """
  end

  @doc "A summary's story, or nil for a summary without one."
  @spec story_of(String.t() | nil) :: Story.t() | nil
  def story_of(nil), do: nil

  def story_of(text) do
    case Story.split(text) do
      %{groups: []} -> nil
      story -> story
    end
  end

  defp story({:ok, text}), do: story_of(text)

  defp story(_state), do: nil

  @doc "▸ when a <details> is closed, ▾ when open; its <details> carries `group`."
  def disclosure_mark(assigns) do
    ~H"""
    <span aria-hidden="true" class="inline-block w-4 group-open:hidden">▸</span><span
      aria-hidden="true"
      class="hidden w-4 group-open:inline-block"
    >▾</span>
    """
  end

  # Parts headed by "## " lines (the first part has no heading), each split into
  # paragraphs and lists.
  defp summary_sections(text) do
    text
    |> String.split(~r/^##[ \t]+(.+)$/m, include_captures: true)
    |> Enum.map(&String.trim/1)
    |> then(fn [first | rest] ->
      headed =
        rest
        |> Enum.chunk_every(2, 2, [""])
        |> Enum.map(fn ["##" <> heading, body] -> {String.trim(heading), body} end)

      [{nil, first} | headed]
    end)
    |> Enum.reject(fn {heading, body} -> is_nil(heading) and body == "" end)
    |> Enum.map(fn {heading, body} -> {heading, summary_parts(body)} end)
  end

  # Paragraphs on blank lines; consecutive lines starting "- " become one list.
  defp summary_parts(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.flat_map(fn chunk ->
      chunk
      |> String.split("\n", trim: true)
      |> Enum.chunk_by(&String.starts_with?(&1, "- "))
      |> Enum.map(fn
        ["- " <> _ | _] = items -> {:list, Enum.map(items, &String.trim_leading(&1, "- "))}
        lines -> {:para, Enum.join(lines, " ")}
      end)
    end)
  end

  @terms [
    {~r/cloture/i, "What is cloture?",
     "A cloture vote decides whether to end debate on a matter so it can move to a final vote."},
    {~r/motion to proceed/i, "What is a motion to proceed?",
     "A vote on whether to start debating a bill or other measure."},
    {~r/motion to table/i, "What does it mean to table?",
     "A vote to set a proposal aside, which usually ends it."},
    {~r/motion to discharge/i, "What is a motion to discharge?",
     "A vote to take a measure away from a committee and bring it to the full chamber."},
    {~r/nomination/i, "What is a nomination vote?",
     "A vote on whether to confirm a person nominated to a public office, such as a judge or an agency head."}
  ]

  attr :id, :string, required: true
  attr :question, :string, default: nil

  @doc """
  A plain definition of the procedure a vote's question names (cloture, motion to
  proceed, ...), folded under "What is ...?". What it is, never why it is used.
  """
  def term_note(assigns) do
    assigns =
      assign(
        assigns,
        :term,
        Enum.find(@terms, fn {pattern, _, _} ->
          is_binary(assigns.question) and assigns.question =~ pattern
        end)
      )

    ~H"""
    <details
      :if={@term}
      id={@id}
      class="text-[13px] text-floor-ink-2"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary class="cursor-pointer text-floor-muted">{elem(@term, 1)}</summary>
      <p class="m-0 mt-1">{elem(@term, 2)}</p>
    </details>
    """
  end

  attr :vote, :map, required: true

  @doc """
  What a vote was on when it is not simply the bill (an amendment's purpose, a
  nominee), with the official page for it when known.
  """
  def vote_subject(assigns) do
    ~H"""
    <p :if={subject?(@vote)} class="m-0 text-[14px] text-floor-ink-2">
      {@vote.description}
      <a :if={@vote.subject_url} href={@vote.subject_url} class="ml-1 font-semibold text-floor-accent">
        Official page ›
      </a>
    </p>
    """
  end

  # passage votes' descriptions repeat the bill's title
  defp subject?(%{description: d, classification: c}),
    do: is_binary(d) and d != "" and c != "passage"

  defp subject?(_vote), do: false
end
