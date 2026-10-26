defmodule EverydayCitizenWeb.BillTextComponents do
  @moduledoc """
  The bill page's text: the contents list (wide screens), and the text by
  section with the version picker, each section's origin and history panel,
  its plain-English summary when opened, and the section's text by level.
  """
  use EverydayCitizenWeb, :html

  import EverydayCitizenWeb.BillHistoryComponents

  alias EverydayCitizenWeb.AiSummary

  attr :bill, :map, required: true
  attr :version, :map, default: nil
  attr :sections, :list, required: true
  attr :open, :any, required: true

  @doc "The contents list beside the text, linking each section."
  def bill_contents(assigns) do
    ~H"""
    <nav
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
          patch={section_path(@bill, @version, i)}
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
    """
  end

  attr :bill, :map, required: true
  attr :versions, :list, required: true
  attr :version, :map, default: nil
  attr :sections, :list, required: true
  attr :open, :any, required: true
  attr :origins, :map, required: true
  attr :version_dates, :map, required: true
  attr :history, :map, default: nil
  attr :change_summary, :any, default: nil
  attr :summaries, :map, required: true
  attr :report, :any, required: true, doc: "fn kind, subject -> the \"Report a problem\" map"

  @doc "The text of the bill by section, with the version picker."
  def bill_text(assigns) do
    ~H"""
    <section
      aria-label="Text of the bill"
      class="order-5 lg:order-2 pb-5 flex flex-col gap-3 lg:gap-4"
    >
      <h2 class="m-0 text-[18px] lg:text-[22px] font-bold">Text of the bill</h2>
      <p :if={@versions == []} class="m-0 text-[15px] text-floor-muted">
        No text published yet.
      </p>
      <div :if={@versions != []} class="flex flex-wrap items-end gap-2.5">
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
              :for={v <- @versions}
              value={v.code}
              selected={@version && v.code == @version.code}
            >
              {version_label(v)}
            </option>
          </select>
        </form>
        <.link
          :if={@sections != []}
          patch={section_path(@bill, @version, if(@open == :all, do: nil, else: "all"))}
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
                  @bill,
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
                  prompt_url={AiSummary.prompt_url(:change)}
                  report={@report.(:change, elem(@change_summary, 0))}
                />
              </:explanation>
            </.origin_panel>
            <.section_summary
              :if={open?(@open, i) and Map.has_key?(@summaries, i)}
              index={i}
              state={@summaries[i]}
              prompt_url={AiSummary.prompt_url(:section)}
              report={@report.(:section, "section:#{@version.id}:#{i}")}
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
    """
  end

  # the bill page's path for a version and an open section (or "all")
  defp section_path(bill, version, enum) do
    ~p"/bills/#{bill.external_id}?#{Enum.reject([version: version && version.code, section: enum], &is_nil(elem(&1, 1)))}"
  end

  defp open?(open, i), do: open == :all or open == i

  defp contents_label(%{"enum" => enum, "heading" => heading}),
    do:
      [enum && String.trim_trailing(enum, "."), heading]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

  defp toggle(true), do: "−"
  defp toggle(false), do: "+"

  defp version_label(v),
    do: "#{v.classification || v.code}#{if v.date, do: " · #{short_date(v.date)}"}"

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
end
