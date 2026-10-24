defmodule EverydayCitizen.Legislature.Person do
  @moduledoc "A legislator."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "people" do
    field :name, :string
    field :given_name, :string
    field :family_name, :string
    field :image_url, :string
    has_many :identifiers, EverydayCitizen.Legislature.PersonIdentifier
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name, :given_name, :family_name, :image_url, :source_id])
    |> validate_required([:name, :source_id])
  end
end
