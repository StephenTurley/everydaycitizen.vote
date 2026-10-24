defmodule EverydayCitizen.Repo do
  use Ecto.Repo,
    otp_app: :everyday_citizen,
    adapter: Ecto.Adapters.Postgres
end
