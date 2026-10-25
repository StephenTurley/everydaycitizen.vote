defmodule EverydayCitizen.Legislation.BillCommitteeActivity do
  @moduledoc "A committee's step on a bill: referred, markup, reported or other, with its date."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "bill_committee_activities" do
    # the committee's code in the source, kept when the committee is not stored
    field :body_ref, :string
    field :kind, :string
    field :date, :date
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :body, EverydayCitizen.Legislature.Body
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end
end
