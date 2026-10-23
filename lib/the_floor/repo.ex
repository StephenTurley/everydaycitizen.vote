defmodule TheFloor.Repo do
  use Ecto.Repo,
    otp_app: :the_floor,
    adapter: Ecto.Adapters.Postgres
end
