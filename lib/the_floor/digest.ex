defmodule TheFloor.Digest do
  @moduledoc """
  What the daily email says: the changes, first stored in a window, to what a
  person follows.

    * a followed bill: a new action, a new text version, a roll call on it;
    * a followed rep: how they voted, a bill they introduced, and progress on
      their bills (as in their feed: reported, scheduled, passed a chamber,
      enrolled, signed, became law).

  "New" is a row's `inserted_at`, never a re-fetch of an unchanged record (bill
  actions are upserted; votes key on the vote's own `inserted_at`, since vote
  positions are rewritten on every fetch). An item reached through both a bill
  and a rep appears once; a followed rep's vote replaces the plain roll-call
  item for the same vote. Items carry their own event dates.
  """
  import Ecto.Query

  alias TheFloor.Accounts.{Scope, User}
  alias TheFloor.Follows
  alias TheFloor.Legislation.{Bill, BillAction, BillVersion, Sponsorship}
  alias TheFloor.Repo
  alias TheFloor.Votes.{Vote, VotePosition}

  @moved ~w(reported scheduled passed_chamber enrolled signed became_law)
  @zone "America/New_York"
  @salt "digest unsubscribe"

  @type item :: %{
          kind: :action | :version | :vote | :rep_vote | :introduced | :rep_bill_moved,
          key: term(),
          date: Date.t() | nil,
          title: String.t(),
          detail: String.t(),
          url: String.t() | nil
        }

  @doc "The items first stored after `since` and up to `until`, newest first."
  @spec items(User.t(), DateTime.t(), DateTime.t()) :: [item()]
  def items(%User{} = user, since, until) do
    scope = Scope.for_user(user)
    bills = Follows.followed_bill_ids(scope)
    people = Follows.followed_person_ids(scope)
    window = {since, until}

    rep_votes = rep_votes(people, window)
    voted = MapSet.new(rep_votes, fn %{key: {:rep_vote, vote_id, _}} -> vote_id end)

    (rep_votes ++
       introduced(people, window) ++
       actions(bills, people, window) ++
       versions(bills, window) ++
       Enum.reject(bill_votes(bills, window), &MapSet.member?(voted, elem(&1.key, 1))))
    |> Enum.uniq_by(& &1.key)
    |> Enum.sort_by(&(&1.date || ~D[0001-01-01]), {:desc, Date})
  end

  @doc "A token for the email's unsubscribe link: never expires, only turns email off."
  @spec unsubscribe_token(User.t()) :: String.t()
  def unsubscribe_token(%User{id: id}), do: Phoenix.Token.sign(TheFloorWeb.Endpoint, @salt, id)

  @spec verify_unsubscribe(String.t()) :: {:ok, integer()} | :error
  def verify_unsubscribe(token) when is_binary(token) do
    case Phoenix.Token.verify(TheFloorWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _ -> :error
    end
  end

  def verify_unsubscribe(_), do: :error

  defp in_window(query, {since, until}),
    do: where(query, [r], r.inserted_at > ^since and r.inserted_at <= ^until)

  # New actions on followed bills, and progress on followed reps' own bills.
  defp actions([], [], _window), do: []

  defp actions(bills, people, window) do
    sponsored =
      from s in Sponsorship,
        where: s.person_id in ^people and s.classification == "primary",
        select: s.bill_id

    BillAction
    |> in_window(window)
    |> where(
      [a],
      a.bill_id in ^bills or (a.bill_id in subquery(sponsored) and a.classification in ^@moved)
    )
    |> preload(:bill)
    |> Repo.all()
    |> Enum.map(fn a ->
      %{
        kind: if(a.bill_id in bills, do: :action, else: :rep_bill_moved),
        key: {:action, a.id},
        date: a.date,
        title: bill_title(a.bill),
        detail: a.description,
        url: bill_path(a.bill)
      }
    end)
  end

  defp versions([], _window), do: []

  defp versions(bills, window) do
    BillVersion
    |> in_window(window)
    |> where([v], v.bill_id in ^bills)
    |> select([v], struct(v, [:id, :bill_id, :code, :classification, :date]))
    |> preload(:bill)
    |> Repo.all()
    |> Enum.map(fn v ->
      %{
        kind: :version,
        key: {:version, v.id},
        date: v.date,
        title: bill_title(v.bill),
        detail: "New text: #{v.classification || v.code}",
        url: bill_path(v.bill)
      }
    end)
  end

  defp bill_votes([], _window), do: []

  defp bill_votes(bills, window) do
    Vote
    |> in_window(window)
    |> where([v], v.bill_id in ^bills)
    |> preload([:bill, :source])
    |> Repo.all()
    |> Enum.map(fn v ->
      %{
        kind: :vote,
        key: {:vote, v.id},
        date: vote_date(v),
        title: bill_title(v.bill),
        detail: "Roll call: #{vote_line(v)}",
        url: bill_path(v.bill)
      }
    end)
  end

  defp rep_votes([], _window), do: []

  defp rep_votes(people, {since, until}) do
    from(p in VotePosition,
      join: v in assoc(p, :vote),
      where: p.person_id in ^people and v.inserted_at > ^since and v.inserted_at <= ^until,
      preload: [:person, vote: [:bill, :source]]
    )
    |> Repo.all()
    |> Enum.map(fn %{vote: v} = p ->
      %{
        kind: :rep_vote,
        key: {:rep_vote, v.id, p.person_id},
        date: vote_date(v),
        title: if(v.bill, do: bill_title(v.bill), else: v.question),
        detail: "#{p.person.name} voted #{option(p.option)}: #{vote_line(v)}",
        url: if(v.bill, do: bill_path(v.bill), else: v.source && v.source.url)
      }
    end)
  end

  defp introduced([], _window), do: []

  defp introduced(people, window) do
    Sponsorship
    |> in_window(window)
    |> where([s], s.person_id in ^people and s.classification == "primary")
    |> preload([:bill, :person])
    |> Repo.all()
    |> Enum.map(fn s ->
      %{
        kind: :introduced,
        key: {:introduced, s.id},
        date: s.date,
        title: bill_title(s.bill),
        detail: "#{s.person.name} introduced this bill",
        url: bill_path(s.bill)
      }
    end)
  end

  defp bill_title(%Bill{identifier: id, title: title}), do: "#{id} · #{title}"
  defp bill_path(%Bill{external_id: id}), do: "/bills/#{id}"

  defp vote_line(%Vote{question: q, result: r, yea_count: y, nay_count: n}),
    do: "#{q}. #{r}, #{y}–#{n}"

  defp vote_date(%Vote{voted_at: nil}), do: nil
  defp vote_date(%Vote{voted_at: at}), do: at |> DateTime.shift_zone!(@zone) |> DateTime.to_date()

  defp option(option) when is_binary(option), do: String.capitalize(option)
  defp option(_), do: "—"
end
