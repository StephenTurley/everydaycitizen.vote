defmodule EverydayCitizen.Legislature.Jurisdiction do
  @moduledoc """
  A legislative jurisdiction. `time_zone` (an IANA name) is the zone its
  legislature keeps its days and clock times in.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "jurisdictions" do
    field :key, :string
    field :name, :string
    field :classification, :string
    field :time_zone, :string
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:key, :name, :classification, :time_zone, :source_id])
    |> validate_required([:key, :name, :classification, :time_zone, :source_id])
    |> validate_inclusion(:classification, ~w(federal state local))
  end
end
