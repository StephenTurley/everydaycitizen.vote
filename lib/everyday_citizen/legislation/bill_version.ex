defmodule EverydayCitizen.Legislation.BillVersion do
  @moduledoc """
  A text version of a bill. Metadata and text are written separately: `source_id`
  is the metadata's provenance, `text_source_id` the text's.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "bill_versions" do
    field :code, :string
    field :classification, :string
    field :date, :date
    field :xml_url, :string
    field :text_url, :string
    field :xml, :string
    field :xml_schema, :string
    field :plain_text, :string
    field :sections, {:array, :map}
    field :sections_version, :integer
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :source, EverydayCitizen.Provenance.Source
    belongs_to :text_source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:bill_id, :code, :classification, :date, :xml_url, :text_url, :source_id])
    |> validate_required([:bill_id, :code, :source_id])
  end

  def text_changeset(struct, attrs) do
    struct
    |> cast(attrs, [:xml, :xml_schema, :plain_text, :sections, :sections_version, :text_source_id])
    |> validate_required([:text_source_id])
    |> validate_inclusion(:xml_schema, ~w(uslm other))
  end
end
