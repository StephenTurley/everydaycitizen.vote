defmodule TheFloor.Follows.Follow do
  @moduledoc "A person following a bill or a rep (exactly one of the two)."
  use Ecto.Schema

  schema "follows" do
    belongs_to :user, TheFloor.Accounts.User
    belongs_to :bill, TheFloor.Legislation.Bill
    belongs_to :person, TheFloor.Legislature.Person

    timestamps(type: :utc_datetime)
  end
end
