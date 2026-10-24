defmodule EverydayCitizen.Legislature.PersonIdentifier do
  @moduledoc "A stable external identifier (`scheme`, `value`) for a person."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "person_identifiers" do
    field :scheme, :string
    field :value, :string
    belongs_to :person, EverydayCitizen.Legislature.Person
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:person_id, :scheme, :value, :source_id])
    |> validate_required([:person_id, :scheme, :value, :source_id])
  end
end
