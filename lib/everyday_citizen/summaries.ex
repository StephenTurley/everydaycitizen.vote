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
  alias EverydayCitizen.Summaries.{AiSummary, Claude, SectionSummary}

  @max_chars 40_000

  @doc "The prompt version a kind of summary is written and looked up with."
  @spec prompt_version(atom()) :: String.t()
  def prompt_version(kind \\ :section), do: Map.fetch!(config(:prompt_versions), kind)

  @doc """
  The version a stored bill or week summary is kept under: its prompt's, and for
  a bill summary its check's too, so a new version of either prompt writes it
  again. A bill's draft (before its check) follows the bill prompt's version.
  """
  @spec cache_version(atom()) :: String.t()
  def cache_version(:bill), do: prompt_version(:bill) <> "+check." <> prompt_version(:bill_check)
  def cache_version(:bill_draft), do: prompt_version(:bill)
  def cache_version(kind), do: prompt_version(kind)

  @doc """
  The text of a section as sent to the model: its number and heading, then each
  block on its own line with its number and heading; text the bill inserts into
  the law is marked `[Inserted into the law: … ]`.
  """
  @spec section_text(map()) :: String.t()
  def section_text(%{"blocks" => _} = section) do
    heading =
      Enum.join(Enum.reject(["Sec. #{section["enum"]}", section["heading"]], &blank?/1), " ")

    Enum.join([heading | section_paragraphs(section)], "\n")
  end

  @doc "How many summaries one visitor may ask for in an hour."
  @spec visitor_limit() :: pos_integer()
  def visitor_limit,
    do: Application.fetch_env!(:everyday_citizen, :summaries)[:visitor_limit] || 30

  @doc "A section's paragraphs, one per block (quoted law bracketed), without its heading."
  @spec section_paragraphs(map()) :: [String.t()]
  def section_paragraphs(%{"blocks" => blocks}) when is_list(blocks),
    do: Enum.flat_map(blocks, &block_lines/1)

  def section_paragraphs(_heading_only), do: []

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
  are configured, or once today's spending budget is used up.
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

  @doc "The model that writes a kind of summary."
  @spec model(atom()) :: String.t()
  def model(kind), do: Map.get(config(:models) || %{}, kind, config(:model))

  @doc """
  Raises unless every model in use has rates, so the app never starts when a
  call would be paid for and then fail to be recorded.
  """
  @spec check_config!() :: :ok
  def check_config! do
    case Enum.reject(models(), &Map.has_key?(config(:rates), &1)) do
      [] -> :ok
      missing -> raise ArgumentError, "no summary rates for #{Enum.join(missing, ", ")}"
    end
  end

  @doc "Every model a kind of summary is written by, the default first."
  @spec models() :: [String.t()]
  def models, do: Enum.uniq([config(:model) | Map.values(config(:models) || %{})])

  @doc "Whether today's spending (the site's day, `Clock.site_zone/0`) has reached `daily_budget_usd`."
  @spec over_budget?() :: boolean()
  def over_budget?, do: spent_today_usd() >= config(:daily_budget_usd)

  @doc """
  Records one Claude call's cost: input and output tokens at the configured
  rates of the kind's model, the long-prompt rates when the input exceeds the
  tier (100K tokens).
  """
  @spec record_usage(atom(), map()) :: :ok
  def record_usage(kind, result) do
    input = result[:input_tokens] || 0
    output = result[:output_tokens] || 0
    rates = Map.fetch!(config(:rates), model(kind))

    {in_rate, out_rate} =
      if input > rates.long_prompt_tokens,
        do: {rates.long_input, rates.long_output},
        else: {rates.input, rates.output}

    # rates are dollars per million tokens, so micro-dollars per token
    cost = round(input * in_rate + output * out_rate)

    Repo.insert_all("ai_usage", [
      %{
        kind: to_string(kind),
        input_tokens: input,
        output_tokens: output,
        cost_micros: cost,
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    :ok
  end

  @doc "Dollars spent on Claude today (the site's day)."
  @spec spent_today_usd() :: float()
  def spent_today_usd do
    micros =
      Repo.one(
        from u in "ai_usage",
          where: u.inserted_at >= ^today_start(),
          select: type(sum(u.cost_micros), :integer)
      )

    (micros || 0) / 1_000_000
  end

  @doc "The cached bill or week summary for that input, or nil."
  @spec get_ai(atom(), String.t(), String.t()) :: AiSummary.t() | nil
  def get_ai(kind, subject, input) do
    Repo.one(
      from s in AiSummary,
        where:
          s.kind == ^to_string(kind) and s.subject == ^subject and
            s.prompt_version == ^cache_version(kind) and s.source_hash == ^hash(input)
    )
  end

  @doc """
  The cached summaries of these subjects under the current prompt version,
  keyed by subject, in one query and without checking them against their text
  (for subjects that name a version whose text does not change).
  """
  @spec cached_ai(atom(), [String.t()]) :: %{String.t() => AiSummary.t()}
  def cached_ai(_kind, []), do: %{}

  def cached_ai(kind, subjects) do
    Repo.all(
      from s in AiSummary,
        where:
          s.kind == ^to_string(kind) and s.subject in ^subjects and
            s.prompt_version == ^cache_version(kind)
    )
    |> Map.new(&{&1.subject, &1})
  end

  @doc """
  A bill or week summary someone is viewing: the cached one, or one queued job
  per subject that writes it and broadcasts on `ai_topic/2`. Not queued without
  credentials or once today's budget is spent.
  """
  @spec request_ai(atom(), String.t(), String.t()) ::
          {:cached, AiSummary.t()} | :queued | :paused | :disabled
  def request_ai(kind, subject, input) do
    cond do
      summary = get_ai(kind, subject, input) ->
        {:cached, summary}

      not Claude.enabled?() ->
        :disabled

      over_budget?() ->
        :paused

      true ->
        %{
          "kind" => to_string(kind),
          "subject" => subject,
          "prompt_version" => cache_version(kind)
        }
        |> EverydayCitizen.Jobs.SummarizeSubject.new()
        |> Oban.insert!()

        :queued
    end
  end

  @doc "The PubSub topic a bill or week summary is broadcast on."
  @spec ai_topic(atom() | String.t(), String.t()) :: String.t()
  def ai_topic(kind, subject), do: "ai_summary:#{kind}:#{subject}"

  @doc "Stores (or replaces) a bill or week summary."
  @spec put_ai(atom(), String.t(), String.t(), map()) :: {:ok, AiSummary.t()}
  def put_ai(kind, subject, input, attrs) do
    row = %AiSummary{
      kind: to_string(kind),
      subject: subject,
      prompt_version: cache_version(kind),
      source_hash: hash(input),
      summary: attrs.summary,
      model: attrs.model,
      input_tokens: attrs[:input_tokens],
      output_tokens: attrs[:output_tokens]
    }

    Repo.insert(row,
      on_conflict:
        {:replace, [:summary, :model, :source_hash, :input_tokens, :output_tokens, :updated_at]},
      conflict_target: [:kind, :subject, :prompt_version],
      returning: true
    )
  end

  @doc "The PubSub topic a section's new summary is broadcast on."
  @spec topic(integer(), non_neg_integer()) :: String.t()
  def topic(version_id, index), do: "section_summary:#{version_id}:#{index}"

  defp today_start, do: EverydayCitizen.Clock.start_of_today(EverydayCitizen.Clock.site_zone())

  defp hash(text), do: :crypto.hash(:sha256, text)

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :summaries)[key]
end
