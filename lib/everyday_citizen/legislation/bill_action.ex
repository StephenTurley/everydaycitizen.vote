defmodule EverydayCitizen.Legislation.BillAction do
  @moduledoc """
  A normalized event in a bill's history. Actions the adapter could not map keep
  their raw text with `classification` nil and `unclassified` true.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @classifications ~w(introduced referred hearing markup reported scheduled passed_chamber
                      amended conference enrolled signed vetoed became_law)

  schema "bill_actions" do
    field :position, :integer
    field :date, :date
    field :description, :string
    field :raw_type, :string
    field :raw_code, :string
    field :classification, :string
    field :unclassified, :boolean, default: false
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :actor_body, EverydayCitizen.Legislature.Body
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :bill_id,
      :actor_body_id,
      :position,
      :date,
      :description,
      :raw_type,
      :raw_code,
      :classification,
      :source_id
    ])
    |> validate_required([:bill_id, :position, :source_id])
    |> validate_inclusion(:classification, @classifications)
    |> flag_unclassified()
  end

  defp flag_unclassified(changeset) do
    put_change(changeset, :unclassified, is_nil(get_field(changeset, :classification)))
  end
end
