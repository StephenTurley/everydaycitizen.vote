defmodule EverydayCitizen.Jobs.ComputeOrigins do
  @moduledoc """
  Works out where each section of every version of a bill came from
  (`BillHistory.all_origins/1`) and stores it on the versions, so a bill page
  reads it instead of reading every version's text. Queued whenever a bill's
  versions change (`enqueue/1`): an origin depends on every earlier version, so
  the whole bill is redone. A bill with one version has nothing to compare and
  is left alone. One job per bill waits at a time; a write while one runs
  queues another, since the running one may have read the old text, and the two
  take turns (a lock per bill) so the newer one writes last.
  """
  use Oban.Worker,
    queue: :text,
    priority: 5,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:bill_id], states: [:available, :scheduled, :retryable]]

  alias EverydayCitizen.{BillHistory, Legislation, Repo}
  alias EverydayCitizen.Legislation.{Bill, BillVersion}

  import Ecto.Query

  # advisory lock namespace for this job (the second key is the bill id)
  @lock 7_161_001

  @doc "Queues the job for a bill."
  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(bill_id), do: Oban.insert(new(%{"bill_id" => bill_id}))

  @doc """
  Queues every bill with more than one version where a version's origins are
  not worked out, or were worked out in an older format
  (`BillHistory.origins_format/0`), unless its job is already waiting. Safe to
  run again.
  """
  @spec fill() :: %{queued: non_neg_integer()}
  def fill do
    format = BillHistory.origins_format()

    several =
      from v in BillVersion, group_by: v.bill_id, having: count(v.id) > 1, select: v.bill_id

    waiting =
      from j in Oban.Job,
        where:
          j.worker == ^inspect(__MODULE__) and j.state in ["available", "scheduled", "retryable"],
        where: not is_nil(fragment("?->>'bill_id'", j.args)),
        select: fragment("(?->>'bill_id')::bigint", j.args)

    ids =
      Repo.all(
        from v in BillVersion,
          where:
            is_nil(v.origins) or
              fragment("(?->>'v')::int IS DISTINCT FROM ?", v.origins, ^format),
          where: v.bill_id in subquery(several) and v.bill_id not in subquery(waiting),
          distinct: true,
          select: v.bill_id
      )

    for chunk <- Enum.chunk_every(ids, 500),
        do: Oban.insert_all(Enum.map(chunk, &new(%{"bill_id" => &1})))

    %{queued: length(ids)}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bill_id" => bill_id}}) do
    {:ok, :ok} =
      Repo.transact(fn ->
        # a second job for the bill waits here for the first, then reads after it
        Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock, bill_id])

        with %Bill{} = bill <- Repo.get(Bill, bill_id),
             true <- several_versions?(bill_id) do
          :ok = Legislation.put_origins(bill.id, encoded(bill))
        end

        {:ok, :ok}
      end)

    :ok
  end

  defp encoded(bill),
    do:
      bill
      |> BillHistory.all_origins()
      |> Map.new(fn {c, o} -> {c, BillHistory.encode_origins(o)} end)

  defp several_versions?(bill_id),
    do: Repo.aggregate(from(v in BillVersion, where: v.bill_id == ^bill_id), :count) > 1
end
