defmodule TheFloor.Adapters.Federal.Jobs do
  @moduledoc """
  Registry of the federal list-level jobs, listed in dependency order
  (jurisdiction first, then members, then what refers to members, then relink and
  coverage). The order is documentation and a priority hint only: list jobs that
  start together finish in any order, so each job enforces its own prerequisites by
  snoozing (`Federal.Prerequisites`), and relink and coverage wait for the other
  ingest jobs. Generic tooling reads it through the `:ingest_adapters` config.
  """
  alias TheFloor.Adapters.Federal.Jobs.{
    Coverage,
    Relink,
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
      {"relink", Relink, %{}},
      {"coverage", Coverage, %{}}
    ]
  end
end
