defmodule EverydayCitizen.Legislation.BillAmendment do
  @moduledoc "An amendment to a bill: its official description, latest action and page."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "bill_amendments" do
    field :external_id, :string
    field :identifier, :string
    field :description, :string
    field :latest_action, :string
    field :latest_action_date, :date
    field :url, :string
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :source, EverydayCitizen.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end
end
