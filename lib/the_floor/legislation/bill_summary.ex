defmodule TheFloor.Legislation.BillSummary do
  @moduledoc """
  An official summary of a bill at one stage, attributed to its `author` and
  stored as sanitized HTML (`TheFloor.Ingest.SafeHtml`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "bill_summaries" do
    field :version_code, :string
    field :action_date, :date
    field :action_description, :string
    field :author, :string
    field :html, :string
    field :updated_at_source, :utc_datetime_usec
    belongs_to :bill, TheFloor.Legislation.Bill
    belongs_to :source, TheFloor.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :bill_id,
      :version_code,
      :action_date,
      :action_description,
      :author,
      :html,
      :updated_at_source,
      :source_id
    ])
    |> validate_required([:bill_id, :author, :html, :source_id])
  end
end
