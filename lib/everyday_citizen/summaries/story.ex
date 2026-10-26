defmodule EverydayCitizen.Summaries.Story do
  @moduledoc """
  A bill summary's parts, as `priv/prompts/bill_summary.v4.md` asks for them:
  the groups of its "If this becomes law" part (each line "- label: sentence"),
  its made-up example, and the rest (the summary, who this affects, words to
  know) with their "## " headings. A reply without the story part has no groups.
  """

  @heading "If this becomes law"
  @example "For example"
  @max_groups 4

  @type group :: %{label: String.t(), sentence: String.t()}
  @type t :: %{groups: [group()], example: String.t() | nil, rest: String.t()}

  @doc "The story part's heading."
  @spec heading() :: String.t()
  def heading, do: @heading

  @spec split(String.t()) :: t()
  def split(text) do
    [first | rest] = String.split(text, ~r/^##[ \t]+(.+)$/m, include_captures: true)

    parts =
      rest
      |> Enum.chunk_every(2, 2, [""])
      |> Enum.map(fn ["##" <> heading, body] -> {String.trim(heading), String.trim(body)} end)

    %{
      groups: groups(find(parts, @heading)),
      example: find(parts, @example),
      rest:
        [
          String.trim(first)
          | for({h, b} <- parts, h not in [@heading, @example], do: "## #{h}\n#{b}")
        ]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
    }
  end

  defp find(parts, heading) do
    Enum.find_value(parts, fn {h, body} -> if h == heading, do: body end)
  end

  defp groups(nil), do: []

  defp groups(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      with "- " <> item <- String.trim(line),
           [label, sentence] <- String.split(item, ":", parts: 2),
           {label, sentence} when label != "" and sentence != "" <-
             {String.trim(label), String.trim(sentence)} do
        [%{label: label, sentence: sentence}]
      else
        _ -> []
      end
    end)
    |> Enum.take(@max_groups)
  end
end
