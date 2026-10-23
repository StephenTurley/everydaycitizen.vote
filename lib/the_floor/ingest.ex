defmodule TheFloor.Ingest do
  @moduledoc """
  Entry point for persisting normalized records produced by adapters.
  Dispatches on the record struct to the writer that owns it.
  """
  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Writer

  @spec write(struct(), integer() | nil) :: {:ok, struct()} | {:error, term()}
  def write(%Records.Jurisdiction{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Body{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.LegislativeSession{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Person{} = r, run_id), do: Writer.Legislature.write(r, run_id)
  def write(%Records.Membership{} = r, run_id), do: Writer.Legislature.write(r, run_id)
end
