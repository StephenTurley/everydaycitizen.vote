defmodule EverydayCitizen.Summaries.Writer do
  @moduledoc """
  Writes a bill's executive summary (or a rep's week summary) with Claude,
  recording the cost of every call and stopping when the day's budget runs out.

  A bill's summary scales with its size (the length band and reply cap below).
  A bill up to #{250_000} characters is sent whole; a longer one is split at
  section breaks into parts of at most that size (each under the model's
  long-prompt price tier), each part summarized in a few bullets, then one
  final call combines the parts' summaries in order. Each part's summary is
  stored by its text's hash, so a retry pays only for the calls still to make.
  """
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Claude

  @max_part 250_000
  # reply caps leave room for the who-it-affects, words and example parts
  @bands [{10_000, "short", 600}, {60_000, "medium", 800}, {250_000, "long", 1200}]
  # a line that starts a section or a larger part: where a long bill is split
  @break ~r/^\s*(SEC\.|Sec\.|SECTION|Section|TITLE|Title|DIVISION|Division|SUBTITLE|Subtitle)\b/

  @type result :: %{
          summary: String.t(),
          model: String.t(),
          input_tokens: integer(),
          output_tokens: integer()
        }

  @doc "The length band and reply cap for a bill of this text."
  @spec band(String.t()) :: {String.t(), pos_integer()}
  def band(text) do
    size = String.length(text)

    Enum.find_value(@bands, {"very long", 1700}, fn {max, name, cap} ->
      if size <= max, do: {name, cap}
    end)
  end

  @spec write(:bill | :rep_week, String.t()) :: {:ok, result()} | {:error, term()}
  def write(:rep_week, input), do: call(:rep_week, input, [])

  def write(:bill, text) do
    {name, cap} = band(text)
    opts = [note: "Length: #{name}", max_tokens: cap]

    if String.length(text) <= @max_part,
      do: call(:bill, text, opts),
      else: write_in_parts(text, opts)
  end

  defp write_in_parts(text, opts) do
    text
    |> parts()
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, done} ->
      case part_summary(part) do
        {:ok, result} -> {:cont, {:ok, [result | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} ->
        done = Enum.reverse(done)
        combined = Enum.map_join(done, "\n", &"<part>\n#{&1.summary}\n</part>")

        with {:ok, final} <- call(:bill, combined, opts) do
          {:ok,
           %{
             final
             | input_tokens: total(done, final, :input_tokens),
               output_tokens: total(done, final, :output_tokens)
           }}
        end

      error ->
        error
    end
  end

  defp part_summary(part) do
    subject = "part:" <> Base.encode16(:crypto.hash(:sha256, part), case: :lower)

    case Summaries.get_ai(:bill_chunk, subject, part) do
      nil ->
        with {:ok, result} <- call(:bill_chunk, part, []) do
          {:ok, _} = Summaries.put_ai(:bill_chunk, subject, part, result)
          {:ok, result}
        end

      # bought on an earlier attempt
      cached ->
        {:ok, %{summary: cached.summary, model: cached.model, input_tokens: 0, output_tokens: 0}}
    end
  end

  defp total(parts, final, key), do: Enum.sum(Enum.map([final | parts], &(Map.get(&1, key) || 0)))

  # One call, if the budget allows it; its cost is recorded.
  defp call(kind, input, opts) do
    if Summaries.over_budget?() do
      {:error, :paused}
    else
      with {:ok, result} <- Claude.summarize(input, kind, opts) do
        :ok = Summaries.record_usage(kind, result)
        {:ok, result}
      end
    end
  end

  @doc false
  # Splits text into parts of at most @max_part characters, cutting at the last
  # section break that fits (or at a line, or mid-line for one huge line).
  def parts(text) do
    text
    |> String.split(~r/(?<=\n)/)
    |> Enum.flat_map(&split_long_line/1)
    |> Enum.reduce({[], [], 0}, &add_line/2)
    |> then(fn {parts, current, _} -> Enum.reverse(close(parts, current)) end)
  end

  defp split_long_line(line) do
    if String.length(line) > @max_part,
      do: line |> String.codepoints() |> Enum.chunk_every(@max_part) |> Enum.map(&Enum.join/1),
      else: [line]
  end

  # current is the part being built, newest line first
  defp add_line(line, {parts, current, size}) do
    len = String.length(line)

    if size + len <= @max_part do
      {parts, [line | current], size + len}
    else
      {kept, carried} = cut_at_break(current)
      carried_size = Enum.sum(Enum.map(carried, &String.length/1))

      if carried_size + len <= @max_part,
        do: {close(parts, kept), [line | carried], carried_size + len},
        else: {close(close(parts, kept), carried), [line], len}
    end
  end

  # Moves the lines from the last section break onward into the next part, when
  # the break is not the part's first line.
  defp cut_at_break(current) do
    lines = Enum.reverse(current)

    case Enum.find_index(current, &Regex.match?(@break, &1)) do
      nil -> {current, []}
      from_end -> split_before(lines, length(lines) - 1 - from_end, current)
    end
  end

  # the break is the part's first line: nothing to move
  defp split_before(_lines, 0, current), do: {current, []}

  defp split_before(lines, at, _current) do
    {kept, carried} = Enum.split(lines, at)
    {Enum.reverse(kept), Enum.reverse(carried)}
  end

  defp close(parts, []), do: parts
  defp close(parts, current), do: [current |> Enum.reverse() |> Enum.join() | parts]
end
