defmodule TheFloor.Adapters.Federal.Normalize.SenateVote do
  @moduledoc """
  Normalizes senate.gov roll-call XML: the vote menu (list of roll numbers) and a
  single vote document into a `Records.Vote` with per-member positions keyed by LIS id.
  """
  alias TheFloor.Adapters.Federal.BillId
  alias TheFloor.Ingest.Records.{SourceRef, Vote}

  @months ~w(January February March April May June July August September October November December)

  @options %{
    "Yea" => "yea",
    "Guilty" => "yea",
    "Nay" => "nay",
    "Not Guilty" => "nay",
    "Present" => "present",
    "Not Voting" => "absent"
  }

  @negative ~r/rejected|failed|not (sustained|agreed|confirmed|passed|guilty)|defeated|not invoked/i
  @positive ~r/agreed to|passed|confirmed|adopted|sustained|invoked|guilty|ratified/i

  @doc "Roll numbers listed in a vote menu document, in document order."
  @spec menu(binary()) :: [pos_integer()]
  def menu(xml) do
    xml
    |> parse!()
    |> find("votes")
    |> children("vote")
    |> Enum.map(fn vote -> vote |> text("vote_number") |> String.to_integer() end)
  end

  @spec vote(binary(), SourceRef.t()) :: Vote.t()
  def vote(xml, %SourceRef{} = source) do
    root = parse!(xml)
    congress = root |> text("congress") |> String.to_integer()
    session = text(root, "session")
    roll = root |> text("vote_number") |> String.to_integer()
    result = blank_to_nil(text(root, "vote_result"))

    %Vote{
      jurisdiction: "federal",
      body_external_id: "senate",
      session_identifier: "#{congress}-#{session}",
      external_id: "senate-#{congress}-#{session}-#{roll}",
      identifier: "Roll Call #{roll}",
      question: blank_to_nil(text(root, "question")),
      result: result,
      passed: passed(result),
      voted_at: parse_date!(text(root, "vote_date")),
      bill_external_id: bill_id(root, congress),
      counts: counts(root),
      positions: positions(root),
      source: source
    }
  end

  defp bill_id(root, congress) do
    case find(root, "document") do
      nil ->
        nil

      doc ->
        BillId.from_label(
          "#{text(doc, "document_type")} #{text(doc, "document_number")}",
          congress
        )
    end
  end

  defp counts(root) do
    count = find(root, "count")

    for key <- [:yea, :nay, :present, :absent], into: %{} do
      tag = %{yea: "yeas", nay: "nays", present: "present", absent: "absent"}[key]
      {key, count |> text(tag) |> to_int()}
    end
  end

  defp positions(root) do
    for member <- root |> find("members") |> children("member") do
      raw = text(member, "vote_cast")

      %{
        person: {"lis", text(member, "lis_member_id")},
        raw_label: blank_to_nil(text(member, "member_full")),
        option: Map.get(@options, raw, "absent"),
        raw_option: raw
      }
    end
  end

  defp passed(nil), do: nil

  defp passed(result) do
    cond do
      Regex.match?(@negative, result) -> false
      Regex.match?(@positive, result) -> true
      true -> nil
    end
  end

  # "January 9, 2025, 12:04 PM" in America/New_York.
  defp parse_date!(string) do
    [_, month, day, year, hour, minute, meridiem] =
      Regex.run(~r/^(\w+)\s+(\d+),\s*(\d{4}),\s*(\d+):(\d{2})\s*([AP]M)$/i, String.trim(string))

    month_no = Enum.find_index(@months, &(&1 == month)) + 1
    hour = String.to_integer(hour) |> rem(12)
    hour = if String.upcase(meridiem) == "PM", do: hour + 12, else: hour

    naive =
      NaiveDateTime.new!(
        String.to_integer(year),
        month_no,
        String.to_integer(day),
        hour,
        String.to_integer(minute),
        0
      )

    local =
      case DateTime.from_naive(naive, "America/New_York") do
        {:ok, dt} -> dt
        {:ambiguous, first, _second} -> first
        {:gap, _before, after_gap} -> after_gap
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end

  defp to_int(""), do: 0
  defp to_int(string), do: String.to_integer(string)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(string), do: string

  defp parse!(xml) do
    {:ok, root} = Saxy.SimpleForm.parse_string(xml)
    root
  end

  # Helpers over Saxy.SimpleForm `{name, attrs, children}` nodes.
  defp children({_name, _attrs, kids}, name), do: for({^name, _, _} = k <- kids, do: k)
  defp children(nil, _name), do: []

  defp find({name, _, _} = node, name), do: node

  defp find({_, _, kids}, name) do
    Enum.find_value(kids, fn
      {_, _, _} = kid -> find(kid, name)
      _text -> nil
    end)
  end

  defp find(nil, _name), do: nil

  defp text(node, name) do
    case find(node, name) do
      {_, _, kids} -> kids |> Enum.filter(&is_binary/1) |> Enum.join() |> String.trim()
      nil -> ""
    end
  end
end
