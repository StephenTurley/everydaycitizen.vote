defmodule EverydayCitizen.Summaries do
  @moduledoc """
  Plain-English summaries of bill sections. A summary is written the first time
  someone opens a section and cached under (version, section index, prompt
  version); it is shown only while the section's text still hashes to what was
  summarized, so a re-split or new text gets a fresh summary.
  """
  import Ecto.Query

  alias EverydayCitizen.Jobs.SummarizeSection
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Summaries.{Claude, SectionSummary}

  @max_chars 40_000

  @zone "America/New_York"

  @doc "The prompt version summaries are written and looked up with."
  @spec prompt_version() :: String.t()
  def prompt_version, do: config(:prompt_version)

  @doc """
  The text of a section as sent to the model: its number and heading, then each
  block on its own line with its number and heading; text the bill inserts into
  the law is marked `[Inserted into the law: … ]`.
  """
  @spec section_text(map()) :: String.t()
  def section_text(%{"blocks" => blocks} = section) do
    heading =
      Enum.join(Enum.reject(["Sec. #{section["enum"]}", section["heading"]], &blank?/1), " ")

    Enum.join([heading | Enum.flat_map(blocks, &block_lines/1)], "\n")
  end

  defp block_lines(%{"quote" => quote}),
    do: ["[Inserted into the law:"] ++ Enum.flat_map(quote, &block_lines/1) ++ ["]"]

  defp block_lines(block) do
    label =
      [block["enum"], block["heading"] && "#{block["heading"]}."]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" ")

    [Enum.join(Enum.reject([label, block["text"]], &blank?/1), " ")]
  end

  defp blank?(value), do: value in [nil, ""]

  @doc "The cached summary of that text, or nil."
  @spec get(integer(), non_neg_integer(), String.t()) :: SectionSummary.t() | nil
  def get(version_id, index, text) do
    Repo.one(
      from s in SectionSummary,
        where:
          s.bill_version_id == ^version_id and s.section_index == ^index and
            s.prompt_version == ^prompt_version() and s.source_hash == ^hash(text)
    )
  end

  @doc """
  The current summaries of several sections of a version, in one query:
  `%{index => summary}` for each `{index, text}` whose text still matches.
  """
  @spec get_many(integer(), [{non_neg_integer(), String.t()}]) :: %{
          non_neg_integer() => SectionSummary.t()
        }
  def get_many(_version_id, []), do: %{}

  def get_many(version_id, sections) do
    hashes = Map.new(sections, fn {index, text} -> {index, hash(text)} end)

    from(s in SectionSummary,
      where:
        s.bill_version_id == ^version_id and s.prompt_version == ^prompt_version() and
          s.section_index in ^Map.keys(hashes)
    )
    |> Repo.all()
    |> Enum.filter(&(&1.source_hash == hashes[&1.section_index]))
    |> Map.new(&{&1.section_index, &1})
  end

  @doc "Stores (or replaces) the summary of a section's text."
  @spec put(integer(), non_neg_integer(), String.t(), map()) :: {:ok, SectionSummary.t()}
  def put(version_id, index, text, attrs) do
    row =
      struct(SectionSummary, %{
        bill_version_id: version_id,
        section_index: index,
        prompt_version: prompt_version(),
        source_hash: hash(text),
        summary: attrs.summary,
        model: attrs.model,
        input_tokens: attrs[:input_tokens],
        output_tokens: attrs[:output_tokens]
      })

    Repo.insert(row,
      on_conflict:
        {:replace, [:summary, :model, :source_hash, :input_tokens, :output_tokens, :updated_at]},
      conflict_target: [:bill_version_id, :section_index, :prompt_version],
      returning: true
    )
  end

  @doc """
  A summary of a section someone opened: the cached one, or a queued job that
  writes it (one per section at a time) and broadcasts it on `topic/2`. Not
  queued when the section is over #{@max_chars} characters, when no credentials
  are configured, or once today's `daily_limit` is reached.
  """
  @spec request(integer(), non_neg_integer(), String.t()) ::
          {:cached, SectionSummary.t()} | :queued | :too_long | :paused | :disabled
  def request(version_id, index, text) do
    cond do
      summary = get(version_id, index, text) -> {:cached, summary}
      String.length(text) > @max_chars -> :too_long
      not Claude.enabled?() -> :disabled
      over_budget?() -> :paused
      true -> queue(version_id, index)
    end
  end

  defp queue(version_id, index) do
    %{"version_id" => version_id, "index" => index, "prompt_version" => prompt_version()}
    |> SummarizeSection.new()
    |> Oban.insert!()

    :queued
  end

  @doc "Whether today's `daily_limit` of new summaries is used up."
  @spec over_budget?() :: boolean()
  def over_budget?, do: created_today() >= config(:daily_limit)

  @doc "The PubSub topic a section's new summary is broadcast on."
  @spec topic(integer(), non_neg_integer()) :: String.t()
  def topic(version_id, index), do: "section_summary:#{version_id}:#{index}"

  @doc "How many summaries were written today (America/New_York)."
  @spec created_today() :: non_neg_integer()
  def created_today do
    start = DateTime.now!(@zone) |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], @zone)
    Repo.aggregate(from(s in SectionSummary, where: s.inserted_at >= ^start), :count)
  end

  defp hash(text), do: :crypto.hash(:sha256, text)

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :summaries)[key]
end
