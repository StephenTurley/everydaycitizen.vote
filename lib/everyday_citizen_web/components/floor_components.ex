defmodule EverydayCitizenWeb.FloorComponents do
  @moduledoc """
  The site's page pieces, drawn from the approved mockups: cards, vote chips
  (solid Yea, outlined Nay, gray otherwise: told apart by fill and label, never
  by color alone), section headings and the closing source line.
  """
  use Phoenix.Component

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
          <div class="text-[15px] leading-relaxed text-floor-ink flex flex-col gap-2">
            <div
              :for={{heading, parts} <- summary_sections(text)}
              data-part={heading == "For example" && "example"}
              class={[
                "flex flex-col gap-1.5",
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
          <p class="m-0 text-[12px] text-floor-muted">
            Written by AI from {@source}; it can be wrong.
            <a href={@prompt_url} class="underline">How it's written</a>
          </p>
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
end
