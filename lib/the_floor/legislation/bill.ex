defmodule TheFloor.Legislation.Bill do
  @moduledoc "A bill or resolution."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @classifications ~w(bill resolution joint_resolution concurrent_resolution)

  schema "bills" do
    field :external_id, :string
    field :web_url, :string
    field :identifier, :string
    field :classification, :string
    field :title, :string
    field :subjects, {:array, :string}, default: []
    field :introduced_on, :date
    field :updated_at_source, :utc_datetime_usec
    belongs_to :jurisdiction, TheFloor.Legislature.Jurisdiction
    belongs_to :session, TheFloor.Legislature.Session
    belongs_to :from_body, TheFloor.Legislature.Body
    belongs_to :source, TheFloor.Provenance.Source
    has_many :actions, TheFloor.Legislation.BillAction
    has_many :sponsorships, TheFloor.Legislation.Sponsorship
    has_many :versions, TheFloor.Legislation.BillVersion
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :jurisdiction_id,
      :session_id,
      :from_body_id,
      :external_id,
      :web_url,
      :identifier,
      :classification,
      :title,
      :subjects,
      :introduced_on,
      :updated_at_source,
      :source_id
    ])
    |> validate_required([
      :jurisdiction_id,
      :session_id,
      :external_id,
      :identifier,
      :classification,
      :title,
      :source_id
    ])
    |> validate_inclusion(:classification, @classifications)
  end
end
