defmodule EverydayCitizen.Summaries.Story do
  @moduledoc """
  A bill summary's parts, as `priv/prompts/bill_summary.v4.md` asks for them:
  the groups of its "If this becomes law" part (each line "- label: sentence"),
  its made-up example, its tags (from `tags/0`), its unrelated subjects with the
  sections each comes from ("- Photo ID to vote: SEC. 3"), and the rest (the
  summary, who this affects, words to know) with their "## " headings. A reply
  without the story part has no groups.
  """

  @heading "If this becomes law"
  @example "For example"
  @tags_heading "Tags"
  @subjects_heading "Subjects"
  @max_groups 4
  @max_tags 2

  @tags [
    "Sets rules",
    "Changes benefits",
    "Changes taxes",
    "Spends or authorizes money",
    "Creates or changes a program",
    "Directs an agency",
    "Changes how government works",
    "Cancels a rule or law",
    "Transfers land",
    "Names or honors",
    "States a view",
    "Amends the Constitution",
    "Chamber business"
  ]

  # a section number as the bill gives it: "SEC. 3", "Sec. 401", "Section 12A"
  @section ~r/(?:SEC\.|Sec\.|Section)\s*([0-9]+[A-Za-z]?)/

  @type group :: %{label: String.t(), sentence: String.t()}
  @type subject :: %{name: String.t(), sections: [String.t()]}
  @type t :: %{
          groups: [group()],
          example: String.t() | nil,
          tags: [String.t()],
          subjects: [subject()],
          rest: String.t()
        }

  @doc "The tags a story may carry, in the order the prompt lists them."
  @spec tags() :: [String.t()]
  def tags, do: @tags

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
      tags: tags(find(parts, @tags_heading)),
      subjects: subjects(find(parts, @subjects_heading)),
      rest:
        [
          String.trim(first)
          | for(
              {h, b} <- parts,
              h not in [@heading, @example, @tags_heading, @subjects_heading],
              do: "## #{h}\n#{b}"
            )
        ]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
    }
  end

  @doc """
  The summary with its story's lines replaced by the valid "- label: sentence"
  lines of `lines` (a check's reply), at most `limit` (the lines it was sent), or
  without the story part when none is valid. A summary without the part is
  returned as it is.
  """
  @spec put_groups(String.t(), String.t(), pos_integer()) :: String.t()
  def put_groups(text, lines, limit \\ @max_groups) do
    part = ~r/^##[ \t]+#{@heading}[ \t]*\n.*?(?=^##[ \t]|\z)/ms

    kept =
      lines
      |> labeled_lines()
      |> Enum.take(min(limit, @max_groups))
      |> Enum.map_join("\n", fn {l, s} -> "- #{l}: #{s}" end)

    replacement = if kept == "", do: "", else: "## #{@heading}\n#{kept}\n\n"

    # the first story part takes the lines; any other is dropped
    case Regex.run(part, text, return: :index) do
      # byte offsets, so text before them can hold any character
      [{at, length}] ->
        before = binary_part(text, 0, at)
        rest = binary_part(text, at + length, byte_size(text) - at - length)
        String.trim(before <> replacement <> Regex.replace(part, rest, ""))

      nil ->
        String.trim(text)
    end
  end

  @doc """
  The reply with its subjects' section numbers replaced by "sections not known":
  for a reply written from summaries of a bill's parts, which carry none, so any
  it gives are guesses.
  """
  @spec forget_sections(String.t()) :: String.t()
  def forget_sections(text) do
    Regex.replace(
      ~r/(^##[ \t]+#{@subjects_heading}[ \t]*\n)(.*?)(?=^##[ \t]|\z)/ms,
      text,
      fn _, heading, body ->
        heading <>
          Regex.replace(~r/^(\s*-\s*[^:\n]+):.*$/m, body, "\\1: sections not known")
      end
    )
  end

  @doc "The reply without its Tags and Subjects parts, which are not summary text."
  @spec without_meta(String.t()) :: String.t()
  def without_meta(text) do
    ~r/^##[ \t]+(#{@tags_heading}|#{@subjects_heading})[ \t]*\n.*?(?=^##[ \t]|\z)/ms
    |> Regex.replace(text, "")
    |> String.trim()
  end

  defp find(parts, heading) do
    Enum.find_value(parts, fn {h, body} -> if h == heading, do: body end)
  end

  defp groups(body) do
    body
    |> labeled_lines()
    |> Enum.map(fn {label, sentence} -> %{label: label, sentence: sentence} end)
    |> Enum.take(@max_groups)
  end

  defp tags(nil), do: []

  # one line ("A · B") or one bulleted tag per line
  defp tags(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&(&1 |> String.trim() |> String.trim_leading("- ") |> String.split("·")))
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @tags))
    |> Enum.take(@max_tags)
  end

  defp subjects(body) do
    for {name, where} <- labeled_lines(body),
        do: %{name: name, sections: for([_, n] <- Regex.scan(@section, where), do: n)}
  end

  # "- label: text" lines, each split on its first ": " (a label may hold a time,
  # "12:01"); others are skipped
  defp labeled_lines(nil), do: []

  defp labeled_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      with "- " <> item <- String.trim(line),
           [label, text] <- String.split(item, ": ", parts: 2),
           {label, text} when label != "" and text != "" <-
             {String.trim(label), String.trim(text)} do
        [{label, text}]
      else
        _ -> []
      end
    end)
  end
end
