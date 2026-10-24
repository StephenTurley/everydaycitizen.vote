defmodule EverydayCitizen.Follows.Follow do
  @moduledoc "A person following a bill or a rep (exactly one of the two)."
  use Ecto.Schema

  schema "follows" do
    belongs_to :user, EverydayCitizen.Accounts.User
    belongs_to :bill, EverydayCitizen.Legislation.Bill
    belongs_to :person, EverydayCitizen.Legislature.Person

    timestamps(type: :utc_datetime)
  end
end
