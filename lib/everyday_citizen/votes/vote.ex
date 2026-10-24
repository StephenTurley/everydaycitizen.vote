defmodule EverydayCitizen.Votes.Vote do
  @moduledoc "A recorded vote in a body during a session, with its tallies."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @classifications ~w(passage cloture amendment nomination procedural other)

  @doc "The normalized vote types."
  def classifications, do: @classifications

  schema "votes" do
    field :external_id, :string
    # The source's bill reference (bill external id), kept when the bill is unknown.
    field :bill_ref, :string
    field :identifier, :string
    field :question, :string
    field :classification, :string, default: "other"
    field :result, :string
    field :passed, :boolean
    field :voted_at, :utc_datetime_usec
    field :yea_count, :integer, default: 0
    field :nay_count, :integer, default: 0
    field :present_count, :integer, default: 0
    field :absent_count, :integer, default: 0
    belongs_to :body, EverydayCitizen.Legislature.Body
    belongs_to :session, EverydayCitizen.Legislature.Session
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :source, EverydayCitizen.Provenance.Source
    has_many :positions, EverydayCitizen.Votes.VotePosition
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :body_id,
      :session_id,
      :bill_id,
      :bill_ref,
      :external_id,
      :identifier,
      :question,
      :classification,
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
    |> validate_inclusion(:classification, @classifications)
  end
end
