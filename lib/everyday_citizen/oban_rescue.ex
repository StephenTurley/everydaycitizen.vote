defmodule EverydayCitizen.ObanRescue do
  @moduledoc """
  Releases jobs left `executing` by an app node that has stopped. A deploy (a
  blue-green switch gives every deploy a new machine) or a crash ends a node
  mid-job, and Lifeline only rescues after two hours (long backfills need that
  margin). Each running node records a heartbeat every 30 seconds
  (`EverydayCitizen.NodeHeartbeat`); a job executing on a node with no heartbeat
  in the last two minutes, started more than two minutes ago, goes back to
  `available` and runs again (jobs are idempotent). This works for any number
  of machines, including the old and new ones during a deploy.
  """
  import Ecto.Query

  alias EverydayCitizen.Repo

  @stale_seconds 120

  @doc "Records that `node` is alive at `now`."
  @spec beat(String.t(), DateTime.t()) :: :ok
  def beat(node, now \\ DateTime.utc_now()) when is_binary(node) do
    Repo.insert_all("node_heartbeats", [%{node: node, seen_at: now}],
      on_conflict: [set: [seen_at: now]],
      conflict_target: :node
    )

    :ok
  end

  @doc "Every recorded heartbeat, as `{node, seen_at}`."
  @spec heartbeats() :: [{String.t(), DateTime.t()}]
  def heartbeats,
    do:
      Repo.all(
        from h in "node_heartbeats",
          order_by: h.node,
          select: {h.node, type(h.seen_at, :utc_datetime_usec)}
      )

  @doc """
  Makes jobs executing on nodes without a recent heartbeat available again, and
  forgets heartbeats older than a day; returns how many jobs were released.
  """
  @spec release_orphans(DateTime.t()) :: non_neg_integer()
  def release_orphans(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@stale_seconds)

    alive = from h in "node_heartbeats", where: h.seen_at > ^cutoff, select: h.node

    {count, _} =
      Oban.Job
      |> where([j], j.state == "executing" and j.attempted_at < ^cutoff)
      |> where([j], fragment("?[1]", j.attempted_by) not in subquery(alive))
      |> Repo.update_all(set: [state: "available"])

    Repo.delete_all(from h in "node_heartbeats", where: h.seen_at < ^DateTime.add(now, -1, :day))
    count
  end
end
