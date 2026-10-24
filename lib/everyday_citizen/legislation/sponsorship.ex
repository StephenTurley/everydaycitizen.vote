defmodule EverydayCitizen.Legislation.Sponsorship do
  @moduledoc "A person's sponsorship (primary or cosponsor) of a bill."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "sponsorships" do
    field :classification, :string
    field :date, :date
    field :withdrawn_on, :date
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :person, EverydayCitizen.Legislature.Person
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:bill_id, :person_id, :classification, :date, :withdrawn_on, :source_id])
    |> validate_required([:bill_id, :person_id, :classification, :source_id])
    |> validate_inclusion(:classification, ~w(primary cosponsor))
  end
end
