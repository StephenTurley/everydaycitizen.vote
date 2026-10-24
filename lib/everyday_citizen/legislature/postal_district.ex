defmodule EverydayCitizen.Legislature.PostalDistrict do
  @moduledoc """
  One postal code's overlap with one district, as the share of the postal area's
  land in that district, so a visitor can often be placed by postal code alone.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "postal_districts" do
    field :postal_code, :string
    field :district_key, :string
    field :land_share, :float
    belongs_to :jurisdiction, EverydayCitizen.Legislature.Jurisdiction
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end
end
