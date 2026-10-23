defmodule TheFloor.Ingest.Relink do
  @moduledoc """
  Links rows that were written before what they refer to. A vote stores its
  source's bill reference (`bill_ref`) and each position its person identifier
  (`person_scheme`/`person_value`) even when the bill or person is not stored yet;
  this fills `bill_id` / `person_id` from those references where they are still nil.
  Bills are matched within the vote's jurisdiction (through its body). Safe to run
  any number of times.
  """
  import Ecto.Query

  alias TheFloor.Legislation.Bill
  alias TheFloor.Legislature.{Body, PersonIdentifier}
  alias TheFloor.Repo
  alias TheFloor.Votes.{Vote, VotePosition}

  @spec run() :: {:ok, %{votes: non_neg_integer(), positions: non_neg_integer()}}
  def run do
    now = DateTime.utc_now()

    {votes, _} =
      from(v in Vote,
        join: body in Body,
        on: body.id == v.body_id,
        join: b in Bill,
        on: b.jurisdiction_id == body.jurisdiction_id and b.external_id == v.bill_ref,
        where: is_nil(v.bill_id) and not is_nil(v.bill_ref),
        update: [set: [bill_id: b.id, updated_at: ^now]]
      )
      |> Repo.update_all([])

    {positions, _} =
      from(p in VotePosition,
        join: i in PersonIdentifier,
        on: i.scheme == p.person_scheme and i.value == p.person_value,
        where: is_nil(p.person_id),
        update: [set: [person_id: i.person_id, updated_at: ^now]]
      )
      |> Repo.update_all([])

    {:ok, %{votes: votes, positions: positions}}
  end
end
