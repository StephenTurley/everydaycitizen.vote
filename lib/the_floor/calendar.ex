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

  @doc "Source URLs of the events starting in `[from, to)`, earliest first."
  @spec source_urls(DateTime.t(), DateTime.t()) :: [String.t()]
  def source_urls(from, to) do
    Event
    |> join(:inner, [e], s in assoc(e, :source))
    |> where([e], e.start_at >= ^from and e.start_at < ^to)
    |> order_by([e], asc: e.start_at, asc: e.id)
    |> select([_e, s], s.url)
    |> Repo.all()
  end
end
