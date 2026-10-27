defmodule EverydayCitizen.Jobs.ComputeOrigins do
  @moduledoc """
  Works out where each section of every version of a bill came from
  (`BillHistory.all_origins/1`) and stores it on the versions, so a bill page
  reads it instead of reading every version's text. Queued whenever a bill's
  versions change (`enqueue/1`): an origin depends on every earlier version, so
  the whole bill is redone. One job per bill waits at a time; a write while one
  runs queues another, since the running one may have read the old text.
  """
  use Oban.Worker,
    queue: :text,
    priority: 5,
    max_attempts: 3,
    unique: [period: 300, keys: [:bill_id], states: [:available, :scheduled, :retryable]]

  alias EverydayCitizen.{BillHistory, Legislation, Repo}
  alias EverydayCitizen.Legislation.{Bill, BillVersion}

  import Ecto.Query

  @doc "Queues the job for a bill."
  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(bill_id), do: Oban.insert(new(%{"bill_id" => bill_id}))

  @doc """
  Fills origins not worked out yet: versions of one-version bills get `%{}`
  (nothing to compare) directly, and every other bill with a version missing
  them is queued, unless its job is already waiting. Safe to run again.
  """
  @spec fill() :: %{one_version: non_neg_integer(), queued: non_neg_integer()}
  def fill do
    several =
      from v in BillVersion, group_by: v.bill_id, having: count(v.id) > 1, select: v.bill_id

    {one, _} =
      Repo.update_all(
        from(v in BillVersion, where: is_nil(v.origins) and v.bill_id not in subquery(several)),
        set: [origins: %{}]
      )

    waiting =
      from j in Oban.Job,
        where:
          j.worker == ^inspect(__MODULE__) and j.state in ["available", "scheduled", "retryable"],
        select: fragment("(?->>'bill_id')::bigint", j.args)

    ids =
      Repo.all(
        from v in BillVersion,
          where: is_nil(v.origins) and v.bill_id in subquery(several),
          where: v.bill_id not in subquery(waiting),
          distinct: true,
          select: v.bill_id
      )

    for chunk <- Enum.chunk_every(ids, 500),
        do: Oban.insert_all(Enum.map(chunk, &new(%{"bill_id" => &1})))

    %{one_version: one, queued: length(ids)}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bill_id" => bill_id}}) do
    case Repo.get(Bill, bill_id) do
      nil ->
        :ok

      bill ->
        origins =
          bill
          |> BillHistory.all_origins()
          |> Map.new(fn {c, o} -> {c, BillHistory.encode_origins(o)} end)

        Legislation.put_origins(bill.id, origins)
    end
  end
end
