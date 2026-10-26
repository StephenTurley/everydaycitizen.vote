defmodule EverydayCitizen.Clock do
  @moduledoc """
  Time zones. A legislature's dates are stored as its own dates; a reader's
  zone (from their browser) is used for "today" and for clock times, falling
  back to the legislature's zone. The site's own day (the summary budget, the
  daily email) runs on `config :everyday_citizen, :site_time_zone`.
  """

  @doc "The zone the site's own day runs on."
  @spec site_zone() :: String.t()
  def site_zone, do: Application.fetch_env!(:everyday_citizen, :site_time_zone)

  @doc "Today in `zone`."
  @spec today(String.t()) :: Date.t()
  def today(zone), do: zone |> DateTime.now!() |> DateTime.to_date()

  @doc "Midnight starting today in `zone`, as a UTC moment."
  @spec start_of_today(String.t()) :: DateTime.t()
  def start_of_today(zone),
    do: zone |> today() |> DateTime.new!(~T[00:00:00], zone) |> DateTime.shift_zone!("Etc/UTC")

  @doc "Whether `name` is a zone in the time-zone database."
  @spec zone?(term()) :: boolean()
  def zone?(name) when is_binary(name) and byte_size(name) <= 64,
    do: match?({:ok, _}, DateTime.now(name))

  def zone?(_name), do: false
end
