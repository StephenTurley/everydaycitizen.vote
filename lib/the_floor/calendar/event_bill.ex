defmodule TheFloor.Calendar.EventBill do
  @moduledoc "Link between a calendar event and a bill on its agenda."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "event_bills" do
    belongs_to :event, TheFloor.Calendar.Event
    belongs_to :bill, TheFloor.Legislation.Bill
    belongs_to :source, TheFloor.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:event_id, :bill_id, :source_id])
    |> validate_required([:event_id, :bill_id, :source_id])
  end
end
