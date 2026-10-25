defmodule EverydayCitizen.Calendar do
  @moduledoc "Queries over calendar events."
  import Ecto.Query

  alias EverydayCitizen.Calendar.{Event, EventBill}
  alias EverydayCitizen.Legislation.Sponsorship
  alias EverydayCitizen.Legislature.{Body, Jurisdiction, Membership}
  alias EverydayCitizen.Repo

  @zone "America/New_York"

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

  @doc """
  The jurisdiction's events in the seven days from `from` (America/New_York),
  grouped by day: `[%{date, events}]`, events with their body and bills. With
  `people: ids`, only events on bills they sponsor or cosponsor and meetings of
  committees where they hold a current membership; with `bills: ids`, only
  events linking one of those bills.
  """
  @spec week(String.t(), Date.t(), keyword()) :: [%{date: Date.t(), events: [Event.t()]}]
  def week(jurisdiction_key, %Date{} = from, opts) do
    start = DateTime.new!(from, ~T[00:00:00], @zone) |> DateTime.shift_zone!("Etc/UTC")

    stop =
      DateTime.new!(Date.add(from, 7), ~T[00:00:00], @zone) |> DateTime.shift_zone!("Etc/UTC")

    Event
    |> join(:inner, [e], j in Jurisdiction, on: j.id == e.jurisdiction_id)
    |> where([e, j], j.key == ^jurisdiction_key and e.start_at >= ^start and e.start_at < ^stop)
    |> for_people(opts[:people], from)
    |> for_bills(opts[:bills])
    |> order_by([e], asc: e.start_at, asc: e.id)
    |> preload([:body, event_bills: :bill])
    |> Repo.all()
    |> Enum.group_by(&(&1.start_at |> DateTime.shift_zone!(@zone) |> DateTime.to_date()))
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {date, events} -> %{date: date, events: events} end)
  end

  @doc """
  What is coming up on the floor from `now`: `items`, the first `limit` floor
  events with bills linked (earliest first, with their body and bills), and
  `next`, the earliest floor event with or without bills (nil if none).
  """
  @spec upcoming_floor(pos_integer(), DateTime.t()) :: %{
          items: [Event.t()],
          next: Event.t() | nil
        }
  def upcoming_floor(limit, now \\ DateTime.utc_now()) do
    upcoming =
      Event
      |> where([e], e.classification == "floor" and e.start_at >= ^now)
      |> order_by([e], asc: e.start_at, asc: e.id)

    with_bills = from eb in EventBill, select: eb.event_id

    items =
      upcoming
      |> where([e], e.id in subquery(with_bills))
      |> limit(^limit)
      |> preload([:body, event_bills: :bill])
      |> Repo.all()

    %{items: items, next: upcoming |> limit(1) |> Repo.one()}
  end

  defp for_bills(query, nil), do: query

  defp for_bills(query, bills) do
    linked = from eb in EventBill, where: eb.bill_id in ^bills, select: eb.event_id
    where(query, [e], e.id in subquery(linked))
  end

  defp for_people(query, nil, _on), do: query

  defp for_people(query, people, on) do
    bills =
      from s in Sponsorship,
        join: eb in EventBill,
        on: eb.bill_id == s.bill_id,
        where: s.person_id in ^people and is_nil(s.withdrawn_on),
        select: eb.event_id

    committees =
      from m in Membership,
        join: b in Body,
        on: b.id == m.body_id,
        where: m.person_id in ^people and b.classification in ["committee", "subcommittee"],
        where: is_nil(m.start_date) or m.start_date <= ^on,
        where: is_nil(m.end_date) or m.end_date >= ^on,
        select: m.body_id

    where(query, [e], e.id in subquery(bills) or e.body_id in subquery(committees))
  end
end
