defmodule EverydayCitizen.Ingest.CoverageCheck do
  @moduledoc """
  One comparison of a stored count against the source's count. `expected` is nil
  (and `passed` false) when the source count could not be fetched; `error` says why.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "coverage_checks" do
    field :ingest_run_id, :integer
    field :name, :string
    field :expected, :integer
    field :actual, :integer
    field :tolerance, :float, default: 0.0
    field :passed, :boolean
    field :error, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
