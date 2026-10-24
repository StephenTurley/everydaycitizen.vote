defmodule EverydayCitizen.Activity do
  @moduledoc """
  A person's activity feed, newest first: their votes, the bills they introduced,
  and those bills' progress (reported, scheduled, passed a chamber, enrolled,
  signed) and becoming law. One `union_all` query per page; on a tie in date,
  became-law comes before progress, then introductions, then votes. Vote dates
  are the day in America/New_York. Cosponsored bills are counted, not listed.
  """
  import Ecto.Query

  alias EverydayCitizen.Activity.Item
  alias EverydayCitizen.Legislation.{Bill, BillAction, Sponsorship}
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.{Vote, VotePosition}

  @moved ~w(reported scheduled passed_chamber enrolled signed)
  @atoms %{
    "vote" => :vote,
    "introduced" => :introduced,
    "moved" => :moved,
    "became_law" => :became_law
  }
  @rank %{"vote" => 1, "introduced" => 2, "moved" => 3, "became_law" => 4}
  @kinds %{
    all: ~w(vote introduced moved became_law),
    votes: ~w(vote),
    bills: ~w(introduced moved),
    law: ~w(became_law)
  }

  @type cursor :: String.t()

  @doc """
  A page of the person's activity, newest first. Options: `filter` (`:all`,
  `:votes`, `:bills`, `:law`), `limit` (25), `before` (a cursor from the last
  page), and `from`/`to` (dates, both inclusive) to keep one span such as a week.
  """
  @spec feed(integer(), keyword()) :: %{items: [Item.t()], next: cursor() | nil}
  def feed(person_id, opts) do
    kinds = Map.fetch!(@kinds, Keyword.get(opts, :filter, :all))
    limit = Keyword.get(opts, :limit, 25)

    rows =
      kinds
      |> Enum.map(&source(&1, person_id))
      |> Enum.reduce(fn q, acc -> union_all(acc, ^q) end)
      |> subquery()
      |> within(opts[:from], opts[:to])
      |> before(opts[:before])
      |> order_by([r], desc: r.date, desc: r.rank, desc: r.ref_id)
      |> limit(^(limit + 1))
      |> Repo.all()

    {page, more} = Enum.split(rows, limit)
    %{items: hydrate(page), next: if(more != [], do: encode(List.last(page)))}
  end

  @spec counts(integer()) :: %{sponsored: non_neg_integer(), cosponsored: non_neg_integer()}
  def counts(person_id) do
    Sponsorship
    |> where([s], s.person_id == ^person_id and is_nil(s.withdrawn_on))
    |> group_by([s], s.classification)
    |> select([s], {s.classification, count()})
    |> Repo.all()
    |> Map.new()
    |> then(&%{sponsored: Map.get(&1, "primary", 0), cosponsored: Map.get(&1, "cosponsor", 0)})
  end

  defp source("vote", person_id) do
    from p in VotePosition,
      join: v in Vote,
      on: v.id == p.vote_id,
      where: p.person_id == ^person_id,
      select: %{
        kind: "vote",
        rank: 1,
        ref_id: v.id,
        # voted_at holds UTC without a zone: mark it UTC, then take the Eastern date
        date:
          fragment("((? AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York')::date", v.voted_at),
        bill_id: v.bill_id,
        option: p.option
      }
  end

  defp source("introduced", person_id) do
    from s in Sponsorship,
      where: s.person_id == ^person_id and s.classification == "primary" and not is_nil(s.date),
      select: %{
        kind: "introduced",
        rank: 2,
        ref_id: s.id,
        date: s.date,
        bill_id: s.bill_id,
        option: nil
      }
  end

  # One item per bill, kind and day: several systems often record the same step.
  defp source(kind, person_id) when kind in ["moved", "became_law"] do
    classifications = if kind == "moved", do: @moved, else: ["became_law"]

    from a in BillAction,
      join: s in Sponsorship,
      on: s.bill_id == a.bill_id and s.person_id == ^person_id and s.classification == "primary",
      where: a.classification in ^classifications and not is_nil(a.date),
      group_by: [a.bill_id, a.date],
      select: %{
        kind: type(^kind, :string),
        rank: type(^Map.fetch!(@rank, kind), :integer),
        ref_id: min(a.id),
        date: a.date,
        bill_id: a.bill_id,
        option: nil
      }
  end

  @doc "The date of the person's most recent item, or nil."
  @spec latest_date(integer()) :: Date.t() | nil
  def latest_date(person_id) do
    case feed(person_id, limit: 1).items do
      [item | _] -> item.date
      [] -> nil
    end
  end

  defp within(query, nil, nil), do: query
  defp within(query, from, to), do: where(query, [r], r.date >= ^from and r.date <= ^to)

  defp before(query, nil), do: query

  defp before(query, cursor) do
    {date, rank, id} = decode(cursor)

    where(
      query,
      [r],
      fragment("(?, ?, ?) < (?, ?, ?)", r.date, r.rank, r.ref_id, ^date, ^rank, ^id)
    )
  end

  defp hydrate(rows) do
    bills = load(Bill, Enum.map(rows, & &1.bill_id))
    votes = load(Vote, for(r <- rows, r.kind == "vote", do: r.ref_id))
    actions = load(BillAction, for(r <- rows, r.kind in ["moved", "became_law"], do: r.ref_id))

    for r <- rows do
      %Item{
        kind: Map.fetch!(@atoms, r.kind),
        date: r.date,
        bill: bills[r.bill_id],
        option: r.option,
        vote: if(r.kind == "vote", do: votes[r.ref_id]),
        action: if(r.kind in ["moved", "became_law"], do: actions[r.ref_id])
      }
    end
  end

  defp load(schema, ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    schema
    |> where([r], r.id in ^ids)
    |> Repo.all()
    |> then(&if(schema == Vote, do: Repo.preload(&1, :body), else: &1))
    |> Map.new(&{&1.id, &1})
  end

  defp encode(%{date: date, rank: rank, ref_id: id}), do: "#{Date.to_iso8601(date)}.#{rank}.#{id}"

  defp decode(cursor) do
    [date, rank, id] = String.split(cursor, ".")
    {Date.from_iso8601!(date), String.to_integer(rank), String.to_integer(id)}
  end
end
