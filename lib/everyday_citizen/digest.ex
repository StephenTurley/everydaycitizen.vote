defmodule EverydayCitizen.Digest do
  @moduledoc """
  What the daily email says: the changes, first stored in a window, to what a
  person follows.

    * a followed bill: a new action, a new text version, a roll call on it;
    * a followed rep: how they voted, a bill they introduced, and progress on
      their bills (as in their feed: reported, scheduled, passed a chamber,
      enrolled, signed, became law).

  "New" is a row's `inserted_at`, never a re-fetch of an unchanged record (bill
  actions are upserted; votes key on the vote's own `inserted_at`, since vote
  positions are rewritten on every fetch), and it must also be after the follow
  that brings it in, so following something never emails its history. An item reached through both a bill
  and a rep appears once; a followed rep's vote replaces the plain roll-call
  item for the same vote. Items carry their own event dates.
  """
  import Ecto.Query

  alias EverydayCitizen.Accounts.{Scope, User}
  alias EverydayCitizen.Follows
  alias EverydayCitizen.Follows.Follow
  alias EverydayCitizen.Legislation.{Bill, BillAction, BillVersion, Sponsorship}
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.{Vote, VotePosition}

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
    window = {user.id, since, until}

    rep_votes = rep_votes(people, window)
    voted = MapSet.new(rep_votes, fn %{key: {:rep_vote, vote_id, _}} -> vote_id end)

    (rep_votes ++
       introduced(people, window) ++
       bill_actions(bills, window) ++
       rep_bill_actions(people, window) ++
       versions(bills, window) ++
       Enum.reject(bill_votes(bills, window), &MapSet.member?(voted, elem(&1.key, 1))))
    |> Enum.uniq_by(& &1.key)
    |> Enum.sort_by(&(&1.date || ~D[0001-01-01]), {:desc, Date})
  end

  @doc "A token for the email's unsubscribe link: never expires, only turns email off."
  @spec unsubscribe_token(User.t()) :: String.t()
  def unsubscribe_token(%User{id: id}),
    do: Phoenix.Token.sign(EverydayCitizenWeb.Endpoint, @salt, id)

  @spec verify_unsubscribe(String.t()) :: {:ok, integer()} | :error
  def verify_unsubscribe(token) when is_binary(token) do
    case Phoenix.Token.verify(EverydayCitizenWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _ -> :error
    end
  end

  def verify_unsubscribe(_), do: :error

  defp in_window(query, {_user_id, since, until}),
    do: where(query, [r], r.inserted_at > ^since and r.inserted_at <= ^until)

  # Rows on a followed bill, stored after the person followed it.
  defp after_bill_follow(query, {user_id, _, _}) do
    join(query, :inner, [r], f in Follow,
      on: f.bill_id == r.bill_id and f.user_id == ^user_id and r.inserted_at > f.inserted_at
    )
  end

  # Rows about a followed person (with a `person_id`), stored after following them.
  defp after_person_follow(query, {user_id, _, _}) do
    join(query, :inner, [r], f in Follow,
      on: f.person_id == r.person_id and f.user_id == ^user_id and r.inserted_at > f.inserted_at
    )
  end

  defp bill_actions([], _window), do: []

  defp bill_actions(_bills, window) do
    BillAction
    |> in_window(window)
    |> after_bill_follow(window)
    |> preload(:bill)
    |> Repo.all()
    |> Enum.map(&action_item(&1, :action))
  end

  # Progress on bills a followed rep sponsored, stored after following the rep.
  defp rep_bill_actions([], _window), do: []

  defp rep_bill_actions(_people, {user_id, _, _} = window) do
    from(a in BillAction,
      join: s in Sponsorship,
      on: s.bill_id == a.bill_id and s.classification == "primary",
      join: f in Follow,
      on: f.person_id == s.person_id and f.user_id == ^user_id and a.inserted_at > f.inserted_at,
      where: a.classification in ^@moved,
      distinct: a.id,
      preload: :bill
    )
    |> in_window(window)
    |> Repo.all()
    |> Enum.map(&action_item(&1, :rep_bill_moved))
  end

  defp action_item(a, kind) do
    %{
      kind: kind,
      key: {:action, a.id},
      date: a.date,
      title: bill_title(a.bill),
      detail: a.description,
      url: bill_path(a.bill)
    }
  end

  defp versions([], _window), do: []

  defp versions(_bills, window) do
    BillVersion
    |> in_window(window)
    |> after_bill_follow(window)
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

  defp bill_votes(_bills, window) do
    Vote
    |> in_window(window)
    |> after_bill_follow(window)
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

  defp rep_votes(_people, {user_id, since, until}) do
    from(p in VotePosition,
      join: v in assoc(p, :vote),
      join: f in Follow,
      on: f.person_id == p.person_id and f.user_id == ^user_id and v.inserted_at > f.inserted_at,
      where: v.inserted_at > ^since and v.inserted_at <= ^until,
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

  defp introduced(_people, window) do
    Sponsorship
    |> in_window(window)
    |> after_person_follow(window)
    |> where([s], s.classification == "primary")
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
