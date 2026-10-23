defmodule TheFloor.Calendar.Event do
  @moduledoc """
  A calendar item. `status` is the raw source status (cancelled events keep their row);
  `unresolved_bill_labels` holds bill references that could not be linked to a bill.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @classifications ~w(floor hearing markup other)

  schema "events" do
    field :external_id, :string
    field :classification, :string
    field :raw_classification, :string
    field :status, :string, default: "scheduled"
    field :title, :string
    field :start_at, :utc_datetime_usec
    field :all_day, :boolean, default: false
    field :location, :string
    field :unresolved_bill_labels, {:array, :string}, default: []
    belongs_to :jurisdiction, TheFloor.Legislature.Jurisdiction
    belongs_to :body, TheFloor.Legislature.Body
    belongs_to :source, TheFloor.Provenance.Source
    has_many :event_bills, TheFloor.Calendar.EventBill
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :jurisdiction_id,
      :body_id,
      :external_id,
      :classification,
      :raw_classification,
      :status,
      :title,
      :start_at,
      :all_day,
      :location,
      :unresolved_bill_labels,
      :source_id
    ])
    |> validate_required([
      :jurisdiction_id,
      :external_id,
      :classification,
      :status,
      :start_at,
      :source_id
    ])
    |> validate_inclusion(:classification, @classifications)
  end
end
