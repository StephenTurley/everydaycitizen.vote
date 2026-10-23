defmodule TheFloor.Votes do
  @moduledoc "Queries over votes and their positions."
  import Ecto.Query

  alias TheFloor.Repo
  alias TheFloor.Votes.Vote

  @spec count_votes(integer(), integer()) :: non_neg_integer()
  def count_votes(body_id, session_id) do
    Vote
    |> where([v], v.body_id == ^body_id and v.session_id == ^session_id)
    |> Repo.aggregate(:count)
  end

  @doc "The subset of `external_ids` that already have a stored vote."
  @spec existing_external_ids([String.t()]) :: MapSet.t(String.t())
  def existing_external_ids(external_ids) do
    Vote
    |> where([v], v.external_id in ^external_ids)
    |> select([v], v.external_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "`%{external_id => {yea_count, nay_count}}` for the stored votes among `external_ids`."
  @spec tallies([String.t()]) :: %{String.t() => {integer(), integer()}}
  def tallies(external_ids) do
    Vote
    |> where([v], v.external_id in ^external_ids)
    |> select([v], {v.external_id, {v.yea_count, v.nay_count}})
    |> Repo.all()
    |> Map.new()
  end
end
