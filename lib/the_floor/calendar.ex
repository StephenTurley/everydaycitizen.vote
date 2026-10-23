defmodule TheFloor.Calendar do
  @moduledoc "Queries over calendar events."
  import Ecto.Query

  alias TheFloor.Calendar.Event
  alias TheFloor.Repo

  @doc "Events starting in `[from, to)`, earliest first."
  @spec list_events(DateTime.t(), DateTime.t()) :: [Event.t()]
  def list_events(from, to) do
    Event
    |> where([e], e.start_at >= ^from and e.start_at < ^to)
    |> order_by([e], asc: e.start_at, asc: e.id)
    |> Repo.all()
  end
end
