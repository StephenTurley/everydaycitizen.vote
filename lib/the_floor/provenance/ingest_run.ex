defmodule TheFloor.Provenance.IngestRun do
  @moduledoc "One execution of an ingest job: what ran, when, and the outcome."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "ingest_runs" do
    field :adapter, :string
    field :job, :string
    field :status, Ecto.Enum, values: [:running, :succeeded, :failed], default: :running
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :stats, :map, default: %{}
    field :error, :string
  end
end
