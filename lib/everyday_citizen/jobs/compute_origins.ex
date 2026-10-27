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
  alias EverydayCitizen.Legislation.Bill

  @doc "Queues the job for a bill."
  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(bill_id), do: Oban.insert(new(%{"bill_id" => bill_id}))

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
