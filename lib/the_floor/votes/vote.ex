defmodule TheFloor.Votes.Vote do
  @moduledoc "A recorded vote in a body during a session, with its tallies."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "votes" do
    field :external_id, :string
    field :identifier, :string
    field :question, :string
    field :result, :string
    field :passed, :boolean
    field :voted_at, :utc_datetime_usec
    field :yea_count, :integer, default: 0
    field :nay_count, :integer, default: 0
    field :present_count, :integer, default: 0
    field :absent_count, :integer, default: 0
    belongs_to :body, TheFloor.Legislature.Body
    belongs_to :session, TheFloor.Legislature.Session
    belongs_to :bill, TheFloor.Legislation.Bill
    belongs_to :source, TheFloor.Provenance.Source
    has_many :positions, TheFloor.Votes.VotePosition
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :body_id,
      :session_id,
      :bill_id,
      :external_id,
      :identifier,
      :question,
      :result,
      :passed,
      :voted_at,
      :yea_count,
      :nay_count,
      :present_count,
      :absent_count,
      :source_id
    ])
    |> validate_required([:body_id, :session_id, :external_id, :voted_at, :source_id])
  end
end
