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
end
