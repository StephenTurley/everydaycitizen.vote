defmodule EverydayCitizen.ObanRescue do
  @moduledoc """
  Releases jobs an earlier deploy of this machine left `executing`. A deploy
  stops the machine mid-job, and Lifeline only rescues after two hours (long
  backfills need that margin), so at boot a job still executing under an
  earlier node name of this same machine is orphaned: it goes back to
  `available` and runs again (jobs are idempotent). Jobs on other machines may
  still be running, so they are left to Lifeline.

  The node is Oban's `:node`, `<machine id>-<image tag>` in production; see
  `config/runtime.exs`. Jobs this node has already started name this node.
  """
  import Ecto.Query

  alias EverydayCitizen.Repo

  @doc """
  Makes jobs executing under an earlier node of this machine (same prefix
  before the first `-`, other suffix) available again; returns how many.
  """
  @spec rescue_orphans(String.t()) :: non_neg_integer()
  def rescue_orphans(node) when is_binary(node) do
    machine = node |> String.split("-", parts: 2) |> hd()

    {count, _} =
      Oban.Job
      |> where([j], j.state == "executing")
      |> where([j], fragment("?[1]", j.attempted_by) != ^node)
      |> where([j], like(fragment("?[1]", j.attempted_by), ^"#{machine}-%"))
      |> Repo.update_all(set: [state: "available"])

    count
  end
end
