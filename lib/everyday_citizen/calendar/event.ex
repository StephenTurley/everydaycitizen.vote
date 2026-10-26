defmodule EverydayCitizen.Calendar.Event do
  @moduledoc """
  A calendar item. `status` is the raw source status (cancelled events keep their row);
  `unresolved_bill_labels` holds bill references that could not be linked to a bill.
  `date` is the legislature's own date; `start_at` is set only when the source
  gives a clock time (nil means all day, or no time given).
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
    field :date, :date
    field :start_at, :utc_datetime_usec
    field :location, :string
    field :unresolved_bill_labels, {:array, :string}, default: []
    belongs_to :jurisdiction, EverydayCitizen.Legislature.Jurisdiction
    belongs_to :body, EverydayCitizen.Legislature.Body
    belongs_to :source, EverydayCitizen.Provenance.Source
    has_many :event_bills, EverydayCitizen.Calendar.EventBill
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
      :date,
      :start_at,
      :location,
      :unresolved_bill_labels,
      :source_id
    ])
    |> validate_required([
      :jurisdiction_id,
      :external_id,
      :classification,
      :status,
      :date,
      :source_id
    ])
    |> validate_inclusion(:classification, @classifications)
  end
end
