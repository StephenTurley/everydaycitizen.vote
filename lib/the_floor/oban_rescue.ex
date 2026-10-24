defmodule TheFloor.ObanRescue do
  @moduledoc """
  Releases jobs a previous deploy left `executing`. A deploy stops the old
  machine mid-job, and Lifeline only rescues after two hours (long backfills
  need that margin), so at boot any job still executing on another node is
  orphaned: it goes back to `available` and runs again (jobs are idempotent).

  The node is Oban's `:node`, which production makes unique per deploy (machine
  and image); see `config/runtime.exs`. Jobs this node has already started name
  this node and are left alone.
  """
  import Ecto.Query

  alias TheFloor.Repo

  @doc "Makes jobs executing on any node but `node` available again; returns how many."
  @spec rescue_orphans(String.t()) :: non_neg_integer()
  def rescue_orphans(node) when is_binary(node) do
    {count, _} =
      Oban.Job
      |> where([j], j.state == "executing")
      |> where([j], fragment("?[1]", j.attempted_by) != ^node)
      |> Repo.update_all(set: [state: "available"])

    count
  end
end
