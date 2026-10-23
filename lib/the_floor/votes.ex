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
end
