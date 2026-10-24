defmodule EverydayCitizen.Legislature.Session do
  @moduledoc "A legislative session, optionally nested under a parent session."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "legislative_sessions" do
    field :identifier, :string
    field :name, :string
    field :start_date, :date
    field :end_date, :date
    belongs_to :jurisdiction, EverydayCitizen.Legislature.Jurisdiction
    belongs_to :parent, __MODULE__
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :jurisdiction_id,
      :parent_id,
      :identifier,
      :name,
      :start_date,
      :end_date,
      :source_id
    ])
    |> validate_required([:jurisdiction_id, :identifier, :source_id])
  end
end
