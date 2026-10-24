defmodule EverydayCitizen.Ingest do
  @moduledoc """
  Entry point for persisting normalized records produced by adapters.
  Dispatches on the record struct to the writer that owns it.
  """
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Ingest.Writer

  @spec write(struct(), integer() | nil) :: {:ok, term()} | {:error, term()}
  def write(%Records.PostalDistricts{} = r, run_id), do: Writer.PostalDistricts.write(r, run_id)
  def write(%Records.Jurisdiction{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Body{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.LegislativeSession{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Person{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Membership{} = r, run_id), do: Writer.Legislature.write(r, run_id)

  def write(%Records.Bill{} = r, run_id), do: Writer.Legislation.write(r, run_id)
  def write(%Records.BillActions{} = r, run_id), do: Writer.Legislation.write(r, run_id)
  def write(%Records.BillSummaries{} = r, run_id), do: Writer.Legislation.write(r, run_id)
  def write(%Records.Sponsorships{} = r, run_id), do: Writer.Legislation.write(r, run_id)
  def write(%Records.BillVersion{} = r, run_id), do: Writer.Legislation.write(r, run_id)
  def write(%Records.BillVersionText{} = r, run_id), do: Writer.Legislation.write(r, run_id)

  def write(%Records.Vote{} = r, run_id), do: Writer.Votes.write(r, run_id)
  def write(%Records.Event{} = r, run_id), do: Writer.Calendar.write(r, run_id)

  @doc """
  Runs `fun` in one database transaction: its writes are kept when it returns
  `{:ok, value}` and all undone when it returns `{:error, reason}`, so a record
  written in several parts is never left half-written.
  """
  @spec atomically((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
  def atomically(fun) do
    EverydayCitizen.Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> EverydayCitizen.Repo.rollback(reason)
      end
    end)
  end
end
