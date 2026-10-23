defmodule TheFloor.Votes.VotePosition do
  @moduledoc """
  One member's position on a vote. `person_id` is nil when the person is not known;
  `raw_label` then keeps the source's name for them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @options ~w(yea nay present absent)

  schema "vote_positions" do
    field :raw_label, :string
    field :option, :string
    field :raw_option, :string
    belongs_to :vote, TheFloor.Votes.Vote
    belongs_to :person, TheFloor.Legislature.Person
    belongs_to :source, TheFloor.Provenance.Source
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:vote_id, :person_id, :raw_label, :option, :raw_option, :source_id])
    |> validate_required([:vote_id, :option, :source_id])
    |> validate_inclusion(:option, @options)
  end
end
