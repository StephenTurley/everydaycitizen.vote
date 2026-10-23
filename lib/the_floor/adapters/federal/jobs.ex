defmodule TheFloor.Adapters.Federal.Jobs do
  @moduledoc """
  Registry of the federal list-level jobs, in the order a full ingest should run
  them (jurisdiction first, then members, then what refers to members).
  Generic tooling reads it through the `:ingest_adapters` config.
  """
  alias TheFloor.Adapters.Federal.Jobs.{
    Coverage,
    SyncBills,
    SyncCommitteeMeetings,
    SyncCongress,
    SyncHouseFloor,
    SyncHouseVotes,
    SyncMembers,
    SyncSenateFloor,
    SyncSenateVotes
  }

  @spec all() :: [{String.t(), module(), map()}]
  def all do
    [
      {"congress", SyncCongress, %{}},
      {"members", SyncMembers, %{}},
      {"bills", SyncBills, %{}},
      {"house_votes", SyncHouseVotes, %{}},
      {"senate_votes", SyncSenateVotes, %{}},
      {"committee_meetings", SyncCommitteeMeetings, %{}},
      {"house_floor", SyncHouseFloor, %{}},
      {"senate_floor", SyncSenateFloor, %{}},
      {"coverage", Coverage, %{}}
    ]
  end
end
