defmodule EverydayCitizen.Summaries do
  @moduledoc """
  Plain-English summaries of bill sections. A summary is written the first time
  someone opens a section and cached under (version, section index, prompt
  version); it is shown only while the section's text still hashes to what was
  summarized, so a re-split or new text gets a fresh summary.
  """
  import Ecto.Query

  alias EverydayCitizen.Repo
  alias EverydayCitizen.Summaries.SectionSummary

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

  @doc "How many summaries were written today (America/New_York)."
  @spec created_today() :: non_neg_integer()
  def created_today do
    start = DateTime.now!(@zone) |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], @zone)
    Repo.aggregate(from(s in SectionSummary, where: s.inserted_at >= ^start), :count)
  end

  defp hash(text), do: :crypto.hash(:sha256, text)

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :summaries)[key]
end
