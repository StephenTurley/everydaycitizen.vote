defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateVoteview do
  @moduledoc """
  Normalizes Voteview's Senate bulk files for one congress (rollcalls, votes and
  members CSVs) into `Records.Vote`s keyed like the Senate's own numbering:
  `senate-{congress}-{session}-{clerk roll}`. Voteview numbers roll calls across
  the whole congress; `clerk_rollnumber` is the Senate's per-session number.

  Positions are keyed by bioguide id (the members file maps Voteview's icpsr to
  it). Totals are counted from the positions, so they equal the recorded tally:
  only Yea, Nay and Present are recorded; Not Voting, paired and announced
  positions count as absent and keep their label in `raw_option`. Voteview gives
  only the date of a vote, so `voted_at` is nil.

  Two differences from the Senate's own tally:
  - Voteview's vote file also carries the President's announced position (a
    member of chamber "President"); only Senate members' rows are positions.
  - The Vice President's tie-breaking vote is not in Voteview's rows. A tie that
    passed was broken by the VP voting yea, so the yea total gets one more (no
    position: the VP is not a senator). A tie that failed is left as counted.
  """
  alias EverydayCitizen.Adapters.Federal.{BillId, VoteClassifier, VoteSupport}
  alias EverydayCitizen.Ingest.Records.{SourceRef, Vote}

  NimbleCSV.define(__MODULE__.CSV, separator: ",", escape: "\"")
  alias __MODULE__.CSV

  # Voteview cast codes (https://voteview.com/articles/data_help_votes); 0 is
  # "not a member of the chamber when this vote was taken" and is dropped.
  @casts %{
    "1" => {"yea", "Yea"},
    "2" => {"absent", "Paired Yea"},
    "3" => {"absent", "Announced Yea"},
    "4" => {"absent", "Announced Nay"},
    "5" => {"absent", "Paired Nay"},
    "6" => {"nay", "Nay"},
    "7" => {"present", "Present"},
    "8" => {"present", "Present"},
    "9" => {"absent", "Not Voting"}
  }

  @type files :: %{rollcalls: binary(), votes: binary(), members: binary()}

  @doc "Each roll call's session, Senate roll number and Voteview roll number."
  @spec rollcalls(binary()) :: [
          %{session: pos_integer(), roll: pos_integer(), voteview_roll: pos_integer()}
        ]
  def rollcalls(csv) do
    for row <- rows(csv) do
      %{
        session: int(row["session"]),
        roll: int(row["clerk_rollnumber"]),
        voteview_roll: int(row["rollnumber"])
      }
    end
  end

  @doc "Every roll call in the files as a `Records.Vote`, all with `source`."
  @spec votes(files(), SourceRef.t()) :: [Vote.t()]
  def votes(%{rollcalls: rollcalls, votes: votes, members: members}, %SourceRef{} = source) do
    people = for m <- rows(members), m["chamber"] == "Senate", into: %{}, do: {m["icpsr"], m}
    casts = votes |> rows() |> Enum.group_by(& &1["rollnumber"])

    for row <- rows(rollcalls) do
      positions = positions(Map.get(casts, row["rollnumber"], []), people)
      vote(row, positions, source)
    end
  end

  defp vote(row, positions, source) do
    congress = int(row["congress"])
    session = int(row["session"])
    roll = int(row["clerk_rollnumber"])
    result = VoteSupport.blank_to_nil(row["vote_result"])
    passed = VoteSupport.passed(result)

    %Vote{
      jurisdiction: "federal",
      body_external_id: "senate",
      session_identifier: "#{congress}-#{session}",
      external_id: "senate-#{congress}-#{session}-#{roll}",
      identifier: "Roll Call #{roll}",
      question: VoteSupport.blank_to_nil(row["vote_question"]),
      description: VoteSupport.blank_to_nil(row["vote_desc"] || ""),
      # Voteview runs a nomination's part number onto it (PN9991 is PN999, part 1),
      # so it is kept as given and no page is linked from it
      subject_ref: nomination_ref(row["bill_number"]),
      classification: VoteClassifier.classify(row["vote_question"]),
      result: result,
      passed: passed,
      voted_on: Date.from_iso8601!(row["date"]),
      bill_external_id: BillId.from_label(row["bill_number"], congress),
      counts: positions |> counts() |> vice_president(passed),
      positions: positions,
      source: source
    }
  end

  defp positions(casts, people) do
    for %{"cast_code" => code, "icpsr" => icpsr} <- casts,
        {option, label} <- [Map.get(@casts, code)],
        %{} = person <- [Map.get(people, icpsr)] do
      %{
        person: bioguide(person["bioguide_id"]),
        raw_label: VoteSupport.blank_to_nil(person["bioname"] || ""),
        option: option,
        raw_option: label
      }
    end
  end

  defp bioguide(id) when id in [nil, ""], do: nil
  defp bioguide(id), do: {"bioguide", id}

  defp counts(positions) do
    by_option = Enum.frequencies_by(positions, & &1.option)
    Map.new([:yea, :nay, :present, :absent], &{&1, Map.get(by_option, Atom.to_string(&1), 0)})
  end

  defp vice_president(%{yea: same, nay: same} = counts, true) when same > 0,
    do: %{counts | yea: same + 1}

  defp vice_president(counts, _passed), do: counts

  defp rows(csv) do
    [header | rows] = CSV.parse_string(csv, skip_headers: false)
    Enum.map(rows, &(header |> Enum.zip(&1) |> Map.new()))
  end

  defp int(string), do: String.to_integer(string)

  defp nomination_ref("PN" <> _ = ref), do: ref
  defp nomination_ref(_bill_number), do: nil
end
