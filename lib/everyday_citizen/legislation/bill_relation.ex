defmodule EverydayCitizen.Legislation.BillRelation do
  @moduledoc """
  A measure related to a bill, by its external id: `procedural` when it governs
  how the bill is taken up (such as a rule), else `related`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "bill_relations" do
    field :related_ref, :string
    field :kind, :string
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end
end
