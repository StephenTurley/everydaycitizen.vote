defmodule TheFloor.Adapters.Federal.Normalize.HouseVote do
  @moduledoc """
  Normalizes Congress.gov `house-vote` JSON (beta endpoint) into a `Records.Vote`.

  * `list/1` reads the `/house-vote/{congress}/{session}` listing.
  * `vote/3` combines the detail document (identity, question, per-party totals)
    with the members document (one position per member, keyed by bioguide id).

  The vote's `SourceRef` is the members response's: positions are the bulk of
  the record, so they dominate its provenance. The detail's source is not stored.

  `startDate` carries an explicit UTC offset, so it is converted to UTC directly.
  Speaker-election style votes cast for candidates carry the candidate name in
  `voteCast`; those map to `present` (a vote was cast, but not yea/nay), the raw
  name is kept in `raw_option`, and the candidate totals are counted as `present`.
  """
  alias TheFloor.Adapters.Federal.{BillId, VoteClassifier, VoteSupport}
  alias TheFloor.Ingest.Records.{SourceRef, Vote}

  @options %{
    "Yea" => "yea",
    "Aye" => "yea",
    "Nay" => "nay",
    "No" => "nay",
    "Present" => "present",
    "Not Voting" => "absent"
  }

  @doc "`%{roll, updated_at}` for each item of a vote listing."
  @spec list(map()) :: [%{roll: pos_integer(), updated_at: DateTime.t() | nil}]
  def list(body) do
    for item <- Map.get(body, "houseRollCallVotes", []) do
      %{roll: item["rollCallNumber"], updated_at: parse_datetime(item["updateDate"])}
    end
  end

  @doc "External id of a House roll-call vote."
  @spec external_id(integer(), integer(), integer()) :: String.t()
  def external_id(congress, session, roll), do: "house-#{congress}-#{session}-#{roll}"

  @spec vote(map(), map(), SourceRef.t()) :: Vote.t()
  def vote(%{"houseRollCallVote" => detail}, %{"houseRollCallVoteMemberVotes" => members}, source) do
    %{"congress" => congress, "sessionNumber" => session, "rollCallNumber" => roll} = detail

    %Vote{
      jurisdiction: "federal",
      body_external_id: "house",
      session_identifier: "#{congress}-#{session}",
      external_id: external_id(congress, session, roll),
      identifier: "Roll Call #{roll}",
      question: detail["voteQuestion"],
      classification: VoteClassifier.classify(detail["voteQuestion"]),
      result: detail["result"],
      passed: VoteSupport.passed(detail["result"]),
      voted_at: parse_datetime(detail["startDate"]),
      bill_external_id: bill_id(detail, congress),
      counts: counts(detail["votePartyTotal"] || []),
      positions: positions(members["results"] || []),
      source: source
    }
  end

  defp bill_id(%{"legislationType" => type, "legislationNumber" => number}, congress),
    do: BillId.external_id(congress, type, number)

  defp bill_id(_detail, _congress), do: nil

  defp counts(totals) do
    Enum.reduce(totals, %{yea: 0, nay: 0, present: 0, absent: 0}, fn
      %{"candidate" => _, "total" => total}, acc ->
        Map.update!(acc, :present, &(&1 + total))

      party, acc ->
        %{
          acc
          | yea: acc.yea + party["yeaTotal"],
            nay: acc.nay + party["nayTotal"],
            present: acc.present + party["presentTotal"],
            absent: acc.absent + party["notVotingTotal"]
        }
    end)
  end

  defp positions(results) do
    for member <- results do
      raw = member["voteCast"]

      %{
        person: {"bioguide", member["bioguideID"]},
        raw_label: "#{member["lastName"]} (#{member["voteParty"]}-#{member["voteState"]})",
        option: Map.get(@options, raw, "present"),
        raw_option: raw
      }
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(string) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(string)
    datetime
  end
end
