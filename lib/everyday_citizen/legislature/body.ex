defmodule EverydayCitizen.Legislature.Body do
  @moduledoc "A legislature, chamber, committee or subcommittee."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "bodies" do
    field :external_id, :string
    field :name, :string
    field :classification, :string
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
      :external_id,
      :name,
      :classification,
      :source_id
    ])
    |> validate_required([:jurisdiction_id, :external_id, :name, :classification, :source_id])
    |> validate_inclusion(:classification, ~w(legislature chamber committee subcommittee))
  end
end
