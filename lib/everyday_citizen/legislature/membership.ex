defmodule EverydayCitizen.Legislature.Membership do
  @moduledoc "A person's role in a body over a term."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "memberships" do
    field :role, :string
    field :party, :string
    field :district, :string
    field :start_date, :date
    field :end_date, :date
    belongs_to :person, EverydayCitizen.Legislature.Person
    belongs_to :body, EverydayCitizen.Legislature.Body
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :person_id,
      :body_id,
      :role,
      :party,
      :district,
      :start_date,
      :end_date,
      :source_id
    ])
    |> validate_required([:person_id, :body_id, :role, :source_id])
    |> validate_inclusion(:role, ~w(member chair vice_chair ranking_member))
  end
end
