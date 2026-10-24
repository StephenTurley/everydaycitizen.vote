defmodule EverydayCitizen.Adapters.Federal.Normalize.VoteSubjects do
  @moduledoc """
  Finds the official record a Senate vote was on when it is not a bill, so the
  vote can link it:

    * Nominations. Voteview runs a nomination's part number onto it ("PN9991" is
      PN999, part 1, but "PN1078" is PN1078), so each way of splitting the
      digits is tried against the Congress.gov nomination list, and the one
      whose nominee's name (the text before the first comma) matches the vote's
      description is taken. No match, or a record without a description: no link.
    * Amendments. A bill's amendment list gives each amendment's latest action,
      which ends "Record Vote Number: N" when it was decided by a roll call; the
      action's year gives the session.
  """

  @site "https://www.congress.gov"

  @doc "Congress.gov nomination list items keyed by citation (\"PN999-1\")."
  @spec by_citation([map()]) :: %{String.t() => map()}
  def by_citation(items), do: Map.new(items, &{&1["citation"], &1})

  @doc "The official citation and page for a vote's nomination reference, or nil."
  @spec nomination_link(String.t(), String.t() | nil, %{String.t() => map()}) ::
          {String.t(), String.t()} | nil
  def nomination_link("PN" <> digits, description, by_citation) when is_binary(description) do
    wanted = name(description)

    digits
    |> candidates()
    |> Enum.map(&by_citation[&1])
    |> Enum.filter(&(&1 && wanted != "" && name(&1["description"]) == wanted))
    |> case do
      [record] -> {record["citation"], nomination_url(record)}
      _none_or_several -> nil
    end
  end

  def nomination_link(_ref, _description, _by_citation), do: nil

  # "9991" → PN9991, and each split: PN9-991, PN9, PN99-91, PN99, PN999-1, PN999
  defp candidates(digits) do
    splits =
      for i <- 1..(String.length(digits) - 1)//1,
          {number, part} = String.split_at(digits, i),
          citation <- ["PN#{number}-#{String.to_integer(part)}", "PN#{number}"],
          do: citation

    Enum.uniq(["PN#{digits}" | splits])
  end

  defp name(nil), do: ""

  defp name(description) do
    description
    |> String.split(",", parts: 2)
    |> hd()
    |> String.downcase()
    |> String.replace(~r/[^a-z]/, "")
  end

  defp nomination_url(%{"congress" => congress, "number" => number, "partNumber" => part}) do
    base = "#{@site}/nomination/#{congress}th-congress/#{number}"
    if part in [nil, "", "00"], do: base, else: "#{base}/#{String.to_integer(part)}"
  end

  @doc """
  A bill's amendments decided by a Senate roll call: `{session, roll}` →
  `{reference, official page}`.
  """
  @spec amendment_rolls([map()], integer()) :: %{
          {integer(), integer()} => {String.t(), String.t()}
        }
  def amendment_rolls(amendments, congress) do
    for %{"type" => "SAMDT", "number" => number, "latestAction" => %{} = action} <- amendments,
        [_, roll] <- [Regex.run(~r/Record Vote Number:\s*(\d+)/, action["text"] || "")],
        {:ok, date} <- [Date.from_iso8601(action["actionDate"] || "")],
        into: %{} do
      {{session(date, congress), String.to_integer(roll)},
       {"SAMDT#{number}", "#{@site}/amendment/#{congress}th-congress/senate-amendment/#{number}"}}
    end
  end

  # a congress's first session starts in the odd year 1789 + 2 * (congress - 1)
  defp session(%Date{year: year}, congress), do: year - (1789 + 2 * (congress - 1)) + 1
end
