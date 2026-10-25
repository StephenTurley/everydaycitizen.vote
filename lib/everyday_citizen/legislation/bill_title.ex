defmodule EverydayCitizen.Legislation.BillTitle do
  @moduledoc """
  One of the titles a bill goes by: `official`, `short`, `popular`, or `part`
  (the short title of a portion of the bill). The display title stays on the bill.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "bill_titles" do
    field :title, :string
    field :kind, :string
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end
end
