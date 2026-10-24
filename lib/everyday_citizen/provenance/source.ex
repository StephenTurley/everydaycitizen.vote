defmodule EverydayCitizen.Provenance.Source do
  @moduledoc "A fetched document. Every domain row references one."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sources" do
    field :url, :string
    field :fetched_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :content_hash, :string
    belongs_to :ingest_run, EverydayCitizen.Provenance.IngestRun
  end
end
